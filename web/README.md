# YourDay Web App

A React + Flask web interface for the YourDay iOS app, connecting to the same Firebase project.

## Features
- **Profile** — Player stats, XP bar, level, inventory
- **Garden** — Seasonal island background, grid visualization with seed/seedling/grown stages, rarity borders, seasonal bonuses
- **Leaderboard** — All players or friends-only, ranked by garden value
- **Social** — Search users, send/accept/decline friend requests, remove friends
- **Chat** — Real-time 1-on-1 messaging + group chats (via Firebase JS SDK `onSnapshot`); create groups, manage members, leave groups
- **Notes** — View and delete cloud-synced notes from `users/{uid}/notes`
- **Journal** — Browse journal entries created after completing scheduled tasks
- **Shared Tasks** — Create, accept, complete, and delete tasks shared with friends

## Setup

### 1. Firebase Service Account Key
1. Go to [Firebase Console](https://console.firebase.google.com) → Project Settings → Service Accounts
2. Click "Generate new private key" and download the JSON file
3. Save it as `web/backend/serviceAccountKey.json`

### 2. Firebase Web App ID
The frontend needs a Web App ID. In Firebase Console → Project Settings → General → Your apps:
1. Add a Web app (or use an existing one)
2. Copy the `appId` value
3. Edit `web/frontend/.env` and replace `REPLACE_WITH_WEB_APP_ID` with your actual App ID

### 3. Backend (Flask)
```bash
cd web/backend
python -m venv venv
# Windows:
venv\Scripts\activate
# macOS/Linux:
source venv/bin/activate

pip install -r requirements.txt
python app.py
```
The backend runs on http://localhost:5000

### 4. Frontend (React)
```bash
cd web/frontend
npm install  # already done
npm run dev
```
The frontend runs on http://localhost:5173

## Project Structure
```
web/
├── backend/           # Flask + Firebase Admin SDK
│   ├── app.py         # Main Flask app
│   ├── routes/        # API route blueprints
│   └── ...
└── frontend/          # Vite + React
    ├── src/
    │   ├── pages/     # Full pages
    │   ├── components/ # Reusable UI
    │   ├── hooks/     # Data hooks (including real-time)
    │   └── api/       # Axios API helpers
    └── public/plants/ # Plant PNG images
```

## Notes
- Tasks and Notes are stored locally on-device (SwiftData) — they are **not** accessible via the web app
- Garden, player stats, leaderboard, friends, chat, and shared tasks are all in Firestore and fully available
- The garden view is read-only (no watering/buying from web to avoid sync conflicts with the iOS app)
