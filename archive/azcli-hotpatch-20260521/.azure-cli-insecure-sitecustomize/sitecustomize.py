import os


if os.environ.get("AZ_LOGIN_INSECURE_PATCH") == "1":
    import requests
    import urllib3

    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    _original_request = requests.sessions.Session.request
    _original_merge_environment_settings = requests.sessions.Session.merge_environment_settings

    def _request_without_tls_verification(self, method, url, **kwargs):
        kwargs["verify"] = False
        return _original_request(self, method, url, **kwargs)

    def _merge_environment_settings_without_tls_verification(self, url, proxies, stream, verify, cert):
        settings = _original_merge_environment_settings(self, url, proxies, stream, verify, cert)
        settings["verify"] = False
        return settings

    requests.sessions.Session.request = _request_without_tls_verification
    requests.sessions.Session.merge_environment_settings = _merge_environment_settings_without_tls_verification
