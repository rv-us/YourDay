from flask import Blueprint, jsonify, request
from firebase_admin import firestore
from auth_middleware import require_auth
from models.serializers import serialize_leaderboard_entry

leaderboard_bp = Blueprint("leaderboard", __name__)
db = None


def get_db():
    global db
    if db is None:
        db = firestore.client()
    return db


@leaderboard_bp.route("/api/leaderboard", methods=["GET"])
@require_auth
def get_leaderboard():
    limit = int(request.args.get("limit", 100))
    order_by = request.args.get("orderBy", "gardenValue")
    if order_by not in ("gardenValue", "playerLevel"):
        order_by = "gardenValue"

    docs = (
        get_db()
        .collection("leaderboard_entries")
        .order_by(order_by, direction=firestore.Query.DESCENDING)
        .limit(limit)
        .stream()
    )

    entries = []
    for rank, doc in enumerate(docs, start=1):
        entries.append(serialize_leaderboard_entry(doc, rank=rank))

    return jsonify(entries)


@leaderboard_bp.route("/api/leaderboard/friends", methods=["GET"])
@require_auth
def get_friends_leaderboard():
    uid = request.uid

    # Get friends
    friend_docs = (
        get_db()
        .collection("users")
        .document(uid)
        .collection("friends")
        .where("status", "==", "accepted")
        .stream()
    )
    friend_ids = {doc.id for doc in friend_docs}
    friend_ids.add(uid)  # Include self

    # Fetch all leaderboard entries and filter client-side (Firestore doesn't support IN + orderBy well)
    all_docs = (
        get_db()
        .collection("leaderboard_entries")
        .order_by("gardenValue", direction=firestore.Query.DESCENDING)
        .stream()
    )

    entries = []
    rank = 1
    for doc in all_docs:
        if doc.id in friend_ids:
            entries.append(serialize_leaderboard_entry(doc, rank=rank))
        rank += 1

    return jsonify(entries)
