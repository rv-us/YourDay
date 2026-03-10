from flask import Blueprint, jsonify, request
from firebase_admin import firestore
from auth_middleware import require_auth
from models.serializers import serialize_value

notes_bp = Blueprint("notes", __name__)
db = None


def get_db():
    global db
    if db is None:
        db = firestore.client()
    return db


def serialize_note(doc):
    data = doc.to_dict() or {}
    return {
        "id": doc.id,
        "localNoteId": data.get("localNoteId", doc.id),
        "content": data.get("content", ""),
        "createdAt": serialize_value(data.get("createdAt")),
        "updatedAt": serialize_value(data.get("updatedAt")),
        "fontSize": data.get("fontSize"),
        "schemaVersion": data.get("schemaVersion", 1),
    }


@notes_bp.route("/api/notes", methods=["GET"])
@require_auth
def get_notes():
    uid = request.uid
    docs = (
        get_db()
        .collection("users").document(uid).collection("notes")
        .order_by("createdAt", direction=firestore.Query.DESCENDING)
        .stream()
    )
    return jsonify([serialize_note(doc) for doc in docs])


@notes_bp.route("/api/notes", methods=["POST"])
@require_auth
def save_note():
    uid = request.uid
    body = request.get_json() or {}
    content = body.get("content", "").strip()
    if not content:
        return jsonify({"error": "content is required"}), 400

    local_note_id = body.get("localNoteId")
    if not local_note_id:
        import uuid
        local_note_id = str(uuid.uuid4())

    doc_ref = get_db().collection("users").document(uid).collection("notes").document(local_note_id)
    doc_ref.set({
        "localNoteId": local_note_id,
        "content": content,
        "fontSize": body.get("fontSize"),
        "userId": uid,
        "createdAt": body.get("createdAt") or firestore.SERVER_TIMESTAMP,
        "updatedAt": firestore.SERVER_TIMESTAMP,
        "schemaVersion": 1,
    }, merge=True)
    return jsonify({"success": True, "localNoteId": local_note_id}), 201


@notes_bp.route("/api/notes/<note_id>", methods=["DELETE"])
@require_auth
def delete_note(note_id):
    uid = request.uid
    get_db().collection("users").document(uid).collection("notes").document(note_id).delete()
    return jsonify({"success": True})
