from flask import Flask
from flask_cors import CORS
from firebase_init import initialize_firebase
from config import CORS_ORIGINS, FLASK_PORT

from routes.auth import auth_bp
from routes.player import player_bp
from routes.garden import garden_bp
from routes.leaderboard import leaderboard_bp
from routes.friends import friends_bp
from routes.chat import chat_bp
from routes.shared_tasks import shared_tasks_bp
from routes.groups import groups_bp
from routes.notes import notes_bp
from routes.journal import journal_bp
from routes.tasks import tasks_bp
from routes.dashboard import dashboard_bp


def create_app():
    initialize_firebase()

    app = Flask(__name__)
    CORS(app, origins=CORS_ORIGINS, supports_credentials=True)

    app.register_blueprint(auth_bp)
    app.register_blueprint(player_bp)
    app.register_blueprint(garden_bp)
    app.register_blueprint(leaderboard_bp)
    app.register_blueprint(friends_bp)
    app.register_blueprint(chat_bp)
    app.register_blueprint(shared_tasks_bp)
    app.register_blueprint(groups_bp)
    app.register_blueprint(notes_bp)
    app.register_blueprint(journal_bp)
    app.register_blueprint(tasks_bp)
    app.register_blueprint(dashboard_bp)

    return app


if __name__ == "__main__":
    app = create_app()
    app.run(debug=True, port=FLASK_PORT)
