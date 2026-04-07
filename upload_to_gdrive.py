from pydrive2.auth import GoogleAuth
from pydrive2.drive import GoogleDrive
import os

# Path to your service account JSON file
SERVICE_ACCOUNT_FILE = os.environ.get("GDRIVE_SERVICE_ACCOUNT_JSON", "service_account.json")

# Authenticate
gauth = GoogleAuth()
gauth.LoadServiceConfigFile(SERVICE_ACCOUNT_FILE)  # use your JSON
drive = GoogleDrive(gauth)

# File to upload
file_path = "spotify.png"
file_name_in_drive = "spotify.png"

# Create & upload
file = drive.CreateFile({'title': file_name_in_drive})
file.SetContentFile(file_path)
file.Upload()

print(f"✅ Uploaded {file_name_in_drive} successfully!")
