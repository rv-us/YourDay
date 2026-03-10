from flask import Blueprint, jsonify, request
from firebase_admin import firestore
from auth_middleware import require_auth
from models.serializers import serialize_player_stats

player_bp = Blueprint("player", __name__)
db = None


def get_db():
    global db
    if db is None:
        db = firestore.client()
    return db


@player_bp.route("/api/player/stats", methods=["GET"])
@require_auth
def get_player_stats():
    uid = request.uid
    doc_ref = get_db().collection("users").document(uid).collection("playerData").document("playerStats")
    doc = doc_ref.get()

    if not doc.exists:
        return jsonify({"error": "Player stats not found"}), 404

    return jsonify(serialize_player_stats(doc))
