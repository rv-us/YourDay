from flask import Blueprint, jsonify, request
from firebase_admin import firestore
from auth_middleware import require_auth
from models.serializers import serialize_value

dashboard_bp = Blueprint("dashboard", __name__)
db = None


def get_db():
    global db
    if db is None:
        db = firestore.client()
    return db


@dashboard_bp.route("/api/dashboard/friend-stats", methods=["GET"])
@require_auth
def get_friend_stats():
    uid = request.uid
    db_client = get_db()

    # Get accepted friends
    friend_docs = (
        db_client.collection("users")
        .document(uid)
        .collection("friends")
        .where("status", "==", "accepted")
        .stream()
    )

    cards = []
    for friend_doc in friend_docs:
        friend_id = friend_doc.id
        friend_data = friend_doc.to_dict() or {}
        display_name = friend_data.get("displayName", "")

        # Get friend's playerStats
        stats_doc = (
            db_client.collection("users")
            .document(friend_id)
            .collection("playerData")
            .document("playerStats")
            .get()
        )

        if not stats_doc.exists:
            continue

        stats = stats_doc.to_dict() or {}

        cards.append({
            "friendId": friend_id,
            "displayName": display_name,
            "yesterdayPoints": stats.get("yesterdayPoints", 0),
            "taskStreak": stats.get("taskStreak", 0),
            "completedTasksYesterday": stats.get("completedTasksYesterday", 0),
            "totalTasksYesterday": stats.get("totalTasksYesterday", 0),
            "isNoActivityYesterday": stats.get("completedTasksYesterday", 0) == 0
                and stats.get("totalTasksYesterday", 0) == 0,
            "isStale": False,
            "lastLoginDate": serialize_value(stats.get("lastLoginDate")),
        })

    return jsonify(cards)
