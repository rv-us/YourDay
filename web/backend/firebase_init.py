import os
import firebase_admin
from firebase_admin import credentials
from config import SERVICE_ACCOUNT_KEY_PATH, FIREBASE_PROJECT_ID


def initialize_firebase():
    if firebase_admin._apps:
        return

    key_path = SERVICE_ACCOUNT_KEY_PATH
    if os.path.exists(key_path):
        cred = credentials.Certificate(key_path)
        firebase_admin.initialize_app(cred, {"projectId": FIREBASE_PROJECT_ID})
    else:
        # Fall back to Application Default Credentials (e.g., gcloud auth application-default login)
        firebase_admin.initialize_app(options={"projectId": FIREBASE_PROJECT_ID})
