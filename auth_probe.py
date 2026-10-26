"""Check the Doctolib login state of the automation Chrome profile over CDP.

Opens a short-lived background tab via Target.createTarget(background=True),
evaluates the page through the attached session, then closes the tab. The tab
stays inactive in its window, so the automation Chrome never takes focus.
Purely deterministic: no LLM involved.
"""

import itertools
import json
import re
import time

import requests
import websocket


_MESSAGE_IDS = itertools.count(1)


def _ws_request(ws, method, params=None, session_id=None):
    """Send one CDP command on an open websocket and return its full result."""

    request_id = next(_MESSAGE_IDS)
    message = {"id": request_id, "method": method, "params": params or {}}
    if session_id:
        message["sessionId"] = session_id
    ws.send(json.dumps(message))
    while True:
        response = json.loads(ws.recv())
        if response.get("id") == request_id:
            error = response.get("error")
            if error:
                raise websocket.WebSocketException(f"CDP error: {error}")
            return response.get("result", {})


def cdp_call(ws_url, method, params=None, timeout=10):
    """Send one CDP command on a target websocket and return its result."""

    ws = websocket.create_connection(ws_url, timeout=timeout, suppress_origin=True)
    try:
        return _ws_request(ws, method, params)
    finally:
        ws.close()


def cdp_evaluate(ws_url, expression, timeout=10):
    """Evaluate a JavaScript expression in a CDP target and return its value."""

    result = cdp_call(ws_url, "Runtime.evaluate", {"expression": expression, "returnByValue": True}, timeout)
    return result.get("result", {}).get("value")


def probe_auth_state(cdp_port, account_name, load_timeout=30):
    """Return {"state": "authenticated"|"logged_out"|"unknown", "detail": str}.

    The check tab is created with Target.createTarget(background=True) so it
    never becomes the active tab and never pulls the Chrome window to front.
    """

    base = f"http://127.0.0.1:{cdp_port}"
    try:
        version = requests.get(f"{base}/json/version", timeout=5).json()
        browser_ws_url = version.get("webSocketDebuggerUrl")
    except (requests.RequestException, ValueError) as e:
        return {"state": "unknown", "detail": f"chrome CDP unreachable: {e}"}

    if not browser_ws_url:
        return {"state": "unknown", "detail": "browser has no websocket debugger url"}

    expression = (
        "(() => ({ url: location.href, ready: document.readyState, "
        "text: document.body ? document.body.innerText.slice(0, 6000) : '' }))()"
    )
    ws = None
    target_id = None
    page = None
    deadline = time.monotonic() + load_timeout
    try:
        ws = websocket.create_connection(browser_ws_url, timeout=10, suppress_origin=True)
        target_id = _ws_request(ws, "Target.createTarget", {
            "url": "https://www.doctolib.fr/",
            "background": True,
        })["targetId"]
        session_id = _ws_request(ws, "Target.attachToTarget", {
            "targetId": target_id,
            "flatten": True,
        })["sessionId"]
        while time.monotonic() < deadline:
            time.sleep(2)
            try:
                result = _ws_request(ws, "Runtime.evaluate",
                                     {"expression": expression, "returnByValue": True},
                                     session_id=session_id)
                page = result.get("result", {}).get("value")
            except (websocket.WebSocketException, OSError, json.JSONDecodeError):
                continue
            if page and page.get("ready") == "complete" and "doctolib" in str(page.get("url", "")):
                break
    except (websocket.WebSocketException, OSError, KeyError) as e:
        return {"state": "unknown", "detail": f"chrome CDP call failed: {e}"}
    finally:
        if ws is not None:
            if target_id:
                try:
                    _ws_request(ws, "Target.closeTarget", {"targetId": target_id})
                except (websocket.WebSocketException, OSError):
                    pass
            ws.close()

    if not page or page.get("ready") != "complete":
        return {"state": "unknown", "detail": "page did not finish loading before timeout"}

    text = str(page.get("text", ""))
    has_login = re.search(r"Se connecter", text) is not None
    has_account = account_name.lower() in text.lower()

    if has_account and not has_login:
        state = "authenticated"
    elif has_login and not has_account:
        state = "logged_out"
    else:
        state = "unknown"
    return {"state": state, "detail": f"login_link={has_login} account_name={has_account}"}


def open_login_tab(cdp_port, settle_timeout=30):
    """Open the Doctolib login flow in a visible automation Chrome tab.

    Leaves the tab open so the user can type credentials, and brings the
    window to front via Page.bringToFront.
    """

    base = f"http://127.0.0.1:{cdp_port}"
    try:
        response = requests.put(f"{base}/json/new?https://www.doctolib.fr/", timeout=5)
        response.raise_for_status()
        tab = response.json()
    except (requests.RequestException, ValueError) as e:
        return {"opened": False, "detail": f"chrome CDP unreachable: {e}"}

    tab_id = tab.get("id")
    ws_url = tab.get("webSocketDebuggerUrl")
    if not ws_url:
        return {"opened": False, "detail": "tab has no websocket debugger url"}

    state_expr = (
        "(() => ({ url: location.href, ready: document.readyState, "
        "loginHref: (Array.from(document.querySelectorAll('a')).find(" 
        "a => /se connecter/i.test(a.innerText)) || {}).href || '' }))()"
    )
    deadline = time.monotonic() + settle_timeout
    try:
        while time.monotonic() < deadline:
            time.sleep(2)
            try:
                page = cdp_evaluate(ws_url, state_expr)
            except (websocket.WebSocketException, OSError, json.JSONDecodeError):
                continue
            if page and page.get("ready") == "complete":
                break
        if not page or page.get("ready") != "complete":
            return {"opened": False, "detail": "page did not finish loading"}

        login_href = page.get("loginHref") or ""
        if login_href:
            cdp_call(ws_url, "Page.navigate", {"url": login_href}, timeout=15)
            deadline = time.monotonic() + settle_timeout
            while time.monotonic() < deadline:
                time.sleep(2)
                try:
                    page = cdp_evaluate(ws_url, state_expr)
                except (websocket.WebSocketException, OSError, json.JSONDecodeError):
                    continue
                if page and page.get("ready") == "complete" and "login" in str(page.get("url", "")):
                    break

        cdp_call(ws_url, "Page.bringToFront", timeout=15)
        return {"opened": True, "detail": f"login tab open at {page.get('url', 'doctolib')}"}
    except (websocket.WebSocketException, OSError) as e:
        return {"opened": False, "detail": f"cdp call failed: {e}"}