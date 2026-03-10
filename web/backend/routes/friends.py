from flask import Blueprint, jsonify, request
from firebase_admin import firestore
from auth_middleware import require_auth
from models.serializers import serialize_value
import datetime

friends_bp = Blueprint("friends", __name__)
db = None


def get_db():
    global db
    if db is None:
        db = firestore.client()
    return db


@friends_bp.route("/api/friends", methods=["GET"])
@require_auth
def get_friends():
    uid = request.uid
    docs = (
        get_db()
        .collection("users")
        .document(uid)
        .collection("friends")
        .where("status", "==", "accepted")
        .stream()
    )
    friends = []
    for doc in docs:
        data = doc.to_dict() or {}
        friends.append({
            "userId": doc.id,
            "displayName": data.get("displayName", ""),
            "status": data.get("status", "accepted"),
            "timestamp": serialize_value(data.get("timestamp")),
        })
    return jsonify(friends)


@friends_bp.route("/api/friends/requests", methods=["GET"])
@require_auth
def get_friend_requests():
    uid = request.uid
    docs = (
        get_db()
        .collection("users")
        .document(uid)
        .collection("friend_requests")
        .where("status", "==", "pending")
        .stream()
    )
    requests_list = []
    for doc in docs:
        data = doc.to_dict() or {}
        requests_list.append({
            "requestId": doc.id,
            "fromUserId": data.get("fromUserId", ""),
            "displayName": data.get("displayName", ""),
            "timestamp": serialize_value(data.get("timestamp")),
        })
    return jsonify(requests_list)


@friends_bp.route("/api/friends/search", methods=["GET"])
@require_auth
def search_users():
    uid = request.uid
    query_term = request.args.get("q", "").strip()
    if len(query_term) < 2:
        return jsonify([])

    docs = (
        get_db()
        .collection("leaderboard_entries")
        .where("displayName", ">=", query_term)
        .where("displayName", "<=", query_term + "\uf8ff")
        .limit(10)
        .stream()
    )

    results = []
    for doc in docs:
        if doc.id == uid:
            continue
        data = doc.to_dict() or {}
        results.append({
            "userId": doc.id,
            "displayName": data.get("displayName", ""),
            "playerLevel": data.get("playerLevel", 1),
            "gardenValue": data.get("gardenValue", 0.0),
        })
    return jsonify(results)


@friends_bp.route("/api/friends/request", methods=["POST"])
@require_auth
def send_friend_request():
    uid = request.uid
    body = request.get_json() or {}
    to_display_name = body.get("toDisplayName", "").strip()
    if not to_display_name:
        return jsonify({"error": "toDisplayName is required"}), 400

    # Look up target user in leaderboard_entries
    db_client = get_db()
    target_docs = (
        db_client.collection("leaderboard_entries")
        .where("displayName", "==", to_display_name)
        .limit(1)
        .stream()
    )
    target_doc = next(target_docs, None)
    if target_doc is None:
        return jsonify({"error": "User not found"}), 404

    target_uid = target_doc.id
    if target_uid == uid:
        return jsonify({"error": "Cannot send friend request to yourself"}), 400

    # Get sender's display name
    sender_entry = db_client.collection("leaderboard_entries").document(uid).get()
    sender_name = (sender_entry.to_dict() or {}).get("displayName", "")

    # Write to target user's friend_requests
    req_ref = db_client.collection("users").document(target_uid).collection("friend_requests").document()
    req_ref.set({
        "fromUserId": uid,
        "toUserId": target_uid,
        "displayName": sender_name,
        "status": "pending",
        "timestamp": firestore.SERVER_TIMESTAMP,
    })

    return jsonify({"success": True, "requestId": req_ref.id})


@friends_bp.route("/api/friends/accept", methods=["POST"])
@require_auth
def accept_friend_request():
    uid = request.uid
    body = request.get_json() or {}
    from_user_id = body.get("fromUserId", "").strip()
    if not from_user_id:
        return jsonify({"error": "fromUserId is required"}), 400

    db_client = get_db()

    # Find the request doc
    req_docs = (
        db_client.collection("users")
        .document(uid)
        .collection("friend_requests")
        .where("fromUserId", "==", from_user_id)
        .limit(1)
        .stream()
    )
    req_doc = next(req_docs, None)
    if req_doc is None:
        return jsonify({"error": "Friend request not found"}), 404

    # Get display names from leaderboard_entries
    sender_entry = db_client.collection("leaderboard_entries").document(from_user_id).get()
    sender_name = (sender_entry.to_dict() or {}).get("displayName", "")

    receiver_entry = db_client.collection("leaderboard_entries").document(uid).get()
    receiver_name = (receiver_entry.to_dict() or {}).get("displayName", "")

    now = datetime.datetime.utcnow()
    batch = db_client.batch()

    # Add to requester's friends
    batch.set(
        db_client.collection("users").document(from_user_id).collection("friends").document(uid),
        {"status": "accepted", "displayName": receiver_name, "timestamp": now},
    )
    # Add to acceptor's friends
    batch.set(
        db_client.collection("users").document(uid).collection("friends").document(from_user_id),
        {"status": "accepted", "displayName": sender_name, "timestamp": now},
    )
    # Delete the request
    batch.delete(db_client.collection("users").document(uid).collection("friend_requests").document(req_doc.id))

    batch.commit()
    return jsonify({"success": True})


@friends_bp.route("/api/friends/decline", methods=["POST"])
@require_auth
def decline_friend_request():
    uid = request.uid
    body = request.get_json() or {}
    from_user_id = body.get("fromUserId", "").strip()
    if not from_user_id:
        return jsonify({"error": "fromUserId is required"}), 400

    db_client = get_db()
    req_docs = (
        db_client.collection("users")
        .document(uid)
        .collection("friend_requests")
        .where("fromUserId", "==", from_user_id)
        .limit(1)
        .stream()
    )
    req_doc = next(req_docs, None)
    if req_doc:
        db_client.collection("users").document(uid).collection("friend_requests").document(req_doc.id).delete()

    return jsonify({"success": True})


@friends_bp.route("/api/friends/<friend_id>", methods=["DELETE"])
@require_auth
def remove_friend(friend_id):
    uid = request.uid
    db_client = get_db()
    batch = db_client.batch()

    batch.delete(db_client.collection("users").document(uid).collection("friends").document(friend_id))
    batch.delete(db_client.collection("users").document(friend_id).collection("friends").document(uid))

    batch.commit()
    return jsonify({"success": True})
