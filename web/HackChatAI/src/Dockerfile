# Use the official Selenium standalone Chrome image
FROM selenium/standalone-chrome:latest

# Run as root (this is the default user for this image)
USER root

# Set the working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3-pip \
    python3-venv \
    sqlite3

# Copy the application code
COPY . /app/

# Create and activate a virtual environment, then install dependencies
RUN python3 -m venv venv
RUN . venv/bin/activate && pip install --upgrade pip && pip install -r requirements.txt

# Expose the port the app runs on
EXPOSE 5001

# Set the entry point to run the Flask app
CMD ["sh", "-c", ". venv/bin/activate && python3 app.py"]
