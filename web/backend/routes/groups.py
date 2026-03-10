from flask import Blueprint, jsonify, request
from firebase_admin import firestore
from auth_middleware import require_auth
from models.serializers import serialize_doc, serialize_value
import datetime

groups_bp = Blueprint("groups", __name__)
db = None


def get_db():
    global db
    if db is None:
        db = firestore.client()
    return db


@groups_bp.route("/api/groups", methods=["GET"])
@require_auth
def get_my_groups():
    uid = request.uid
    docs = (
        get_db()
        .collection("group_chats")
        .where("memberIds", "array_contains", uid)
        .order_by("lastMessageAt", direction=firestore.Query.DESCENDING)
        .stream()
    )
    groups = []
    for doc in docs:
        data = doc.to_dict() or {}
        groups.append({
            "id": doc.id,
            "name": data.get("name", ""),
            "adminId": data.get("adminId", ""),
            "memberIds": data.get("memberIds", []),
            "lastMessageText": data.get("lastMessageText", ""),
            "lastMessageAt": serialize_value(data.get("lastMessageAt")),
            "lastMessageSenderId": data.get("lastMessageSenderId", ""),
            "createdAt": serialize_value(data.get("createdAt")),
        })
    return jsonify(groups)


@groups_bp.route("/api/groups", methods=["POST"])
@require_auth
def create_group():
    uid = request.uid
    body = request.get_json() or {}
    name = body.get("name", "").strip()
    member_ids = body.get("memberIds", [])
    member_display_names = body.get("memberDisplayNames", {})

    if not name:
        return jsonify({"error": "name is required"}), 400

    if uid not in member_ids:
        member_ids = [uid] + member_ids

    db_client = get_db()
    now = datetime.datetime.utcnow()
    group_ref = db_client.collection("group_chats").document()
    group_id = group_ref.id

    batch = db_client.batch()
    batch.set(group_ref, {
        "name": name,
        "adminId": uid,
        "memberIds": member_ids,
        "lastMessageText": "",
        "lastMessageAt": now,
        "lastMessageSenderId": "",
        "createdAt": now,
    })

    for member_id in member_ids:
        role = "admin" if member_id == uid else "member"
        display_name = member_display_names.get(member_id, "")
        member_ref = group_ref.collection("members").document(member_id)
        batch.set(member_ref, {
            "displayName": display_name,
            "joinedAt": now,
            "role": role,
        })

    batch.commit()
    return jsonify({"success": True, "groupId": group_id}), 201


@groups_bp.route("/api/groups/<group_id>", methods=["GET"])
@require_auth
def get_group(group_id):
    uid = request.uid
    doc = get_db().collection("group_chats").document(group_id).get()
    if not doc.exists:
        return jsonify({"error": "Group not found"}), 404
    data = doc.to_dict() or {}
    if uid not in data.get("memberIds", []):
        return jsonify({"error": "Not a member of this group"}), 403
    return jsonify({
        "id": doc.id,
        "name": data.get("name", ""),
        "adminId": data.get("adminId", ""),
        "memberIds": data.get("memberIds", []),
        "lastMessageText": data.get("lastMessageText", ""),
        "lastMessageAt": serialize_value(data.get("lastMessageAt")),
        "createdAt": serialize_value(data.get("createdAt")),
    })


@groups_bp.route("/api/groups/<group_id>/messages", methods=["GET"])
@require_auth
def get_group_messages(group_id):
    uid = request.uid
    limit = int(request.args.get("limit", 50))
    db_client = get_db()

    # Verify membership
    group_doc = db_client.collection("group_chats").document(group_id).get()
    if not group_doc.exists or uid not in (group_doc.to_dict() or {}).get("memberIds", []):
        return jsonify({"error": "Not a member of this group"}), 403

    msgs = (
        db_client.collection("group_chats").document(group_id).collection("messages")
        .order_by("timestamp", direction=firestore.Query.ASCENDING)
        .limit(limit)
        .stream()
    )
    return jsonify([serialize_doc(m) for m in msgs])


@groups_bp.route("/api/groups/<group_id>/messages", methods=["POST"])
@require_auth
def send_group_message(group_id):
    uid = request.uid
    body = request.get_json() or {}
    content = body.get("content", "").strip()
    sender_display_name = body.get("senderDisplayName", "")

    if not content:
        return jsonify({"error": "content is required"}), 400

    db_client = get_db()
    group_ref = db_client.collection("group_chats").document(group_id)
    group_doc = group_ref.get()
    if not group_doc.exists or uid not in (group_doc.to_dict() or {}).get("memberIds", []):
        return jsonify({"error": "Not a member of this group"}), 403

    now = datetime.datetime.utcnow()
    batch = db_client.batch()

    msg_ref = group_ref.collection("messages").document()
    batch.set(msg_ref, {
        "senderId": uid,
        "senderDisplayName": sender_display_name,
        "receiverId": "",
        "content": content,
        "timestamp": now,
    })

    batch.update(group_ref, {
        "lastMessageText": content,
        "lastMessageAt": now,
        "lastMessageSenderId": uid,
    })

    batch.commit()
    return jsonify({"success": True, "messageId": msg_ref.id}), 201


@groups_bp.route("/api/groups/<group_id>/members", methods=["GET"])
@require_auth
def get_group_members(group_id):
    uid = request.uid
    db_client = get_db()

    group_doc = db_client.collection("group_chats").document(group_id).get()
    if not group_doc.exists or uid not in (group_doc.to_dict() or {}).get("memberIds", []):
        return jsonify({"error": "Not a member of this group"}), 403

    member_docs = db_client.collection("group_chats").document(group_id).collection("members").stream()
    members = []
    for doc in member_docs:
        data = doc.to_dict() or {}
        members.append({
            "id": doc.id,
            "displayName": data.get("displayName", ""),
            "role": data.get("role", "member"),
            "joinedAt": serialize_value(data.get("joinedAt")),
        })
    return jsonify(members)


@groups_bp.route("/api/groups/<group_id>/leave", methods=["DELETE"])
@require_auth
def leave_group(group_id):
    uid = request.uid
    db_client = get_db()

    group_ref = db_client.collection("group_chats").document(group_id)
    group_doc = group_ref.get()
    if not group_doc.exists:
        return jsonify({"error": "Group not found"}), 404

    data = group_doc.to_dict() or {}
    member_ids = data.get("memberIds", [])
    if uid not in member_ids:
        return jsonify({"error": "Not a member"}), 403

    new_member_ids = [m for m in member_ids if m != uid]
    batch = db_client.batch()
    batch.update(group_ref, {"memberIds": new_member_ids})
    batch.delete(group_ref.collection("members").document(uid))
    batch.commit()
    return jsonify({"success": True})
