from flask import Blueprint, jsonify, request
from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter, Or, And
from auth_middleware import require_auth
from models.serializers import serialize_doc, serialize_value
import datetime

chat_bp = Blueprint("chat", __name__)
db = None


def get_db():
    global db
    if db is None:
        db = firestore.client()
    return db


@chat_bp.route("/api/chat/threads", methods=["GET"])
@require_auth
def get_chat_threads():
    uid = request.uid
    db_client = get_db()

    # Get friends list
    friend_docs = (
        db_client.collection("users")
        .document(uid)
        .collection("friends")
        .where("status", "==", "accepted")
        .stream()
    )
    friends = {doc.id: (doc.to_dict() or {}).get("displayName", "") for doc in friend_docs}

    threads = []
    for friend_id, display_name in friends.items():
        # Get last message
        last_msgs = (
            db_client.collection("chat_messages")
            .where(
                filter=Or([
                    And([FieldFilter("senderId", "==", uid), FieldFilter("receiverId", "==", friend_id)]),
                    And([FieldFilter("senderId", "==", friend_id), FieldFilter("receiverId", "==", uid)]),
                ])
            )
            .order_by("timestamp", direction=firestore.Query.DESCENDING)
            .limit(1)
            .stream()
        )
        last_msg_doc = next(last_msgs, None)
        last_msg = None
        if last_msg_doc:
            data = last_msg_doc.to_dict() or {}
            last_msg = {
                "content": data.get("content", ""),
                "timestamp": serialize_value(data.get("timestamp")),
                "senderId": data.get("senderId", ""),
            }

        threads.append({
            "friendId": friend_id,
            "displayName": display_name,
            "lastMessage": last_msg,
        })

    # Sort threads: those with messages first, newest first
    threads.sort(
        key=lambda t: t["lastMessage"]["timestamp"] if t["lastMessage"] else "",
        reverse=True,
    )
    return jsonify(threads)


@chat_bp.route("/api/chat/<friend_id>/messages", methods=["GET"])
@require_auth
def get_messages(friend_id):
    uid = request.uid
    limit = int(request.args.get("limit", 50))
    db_client = get_db()

    msgs = (
        db_client.collection("chat_messages")
        .where(
            filter=Or([
                And([FieldFilter("senderId", "==", uid), FieldFilter("receiverId", "==", friend_id)]),
                And([FieldFilter("senderId", "==", friend_id), FieldFilter("receiverId", "==", uid)]),
            ])
        )
        .order_by("timestamp", direction=firestore.Query.ASCENDING)
        .limit(limit)
        .stream()
    )

    return jsonify([serialize_doc(m) for m in msgs])


@chat_bp.route("/api/chat/<friend_id>/messages", methods=["POST"])
@require_auth
def send_message(friend_id):
    uid = request.uid
    body = request.get_json() or {}
    content = body.get("content", "").strip()
    if not content:
        return jsonify({"error": "content is required"}), 400

    doc_ref = get_db().collection("chat_messages").document()
    doc_ref.set({
        "senderId": uid,
        "receiverId": friend_id,
        "content": content,
        "timestamp": firestore.SERVER_TIMESTAMP,
    })

    return jsonify({"success": True, "messageId": doc_ref.id}), 201
