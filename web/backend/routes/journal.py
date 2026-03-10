from flask import Blueprint, jsonify, request
from firebase_admin import firestore
from auth_middleware import require_auth
from models.serializers import serialize_value

journal_bp = Blueprint("journal", __name__)
db = None


def get_db():
    global db
    if db is None:
        db = firestore.client()
    return db


def serialize_entry(doc):
    data = doc.to_dict() or {}
    return {
        "id": doc.id,
        "userId": data.get("userId", ""),
        "eventId": data.get("eventId"),
        "taskTitle": data.get("taskTitle", ""),
        "scheduledStartTime": serialize_value(data.get("scheduledStartTime")),
        "scheduledEndTime": serialize_value(data.get("scheduledEndTime")),
        "actualStartTime": serialize_value(data.get("actualStartTime")),
        "actualEndTime": serialize_value(data.get("actualEndTime")),
        "whatDid": data.get("whatDid", ""),
        "howWent": data.get("howWent"),
        "learned": data.get("learned"),
        "distractions": data.get("distractions"),
        "completionStatus": data.get("completionStatus", "completed"),
        "timestamp": serialize_value(data.get("timestamp")),
        "dayOfWeek": data.get("dayOfWeek", ""),
    }


@journal_bp.route("/api/journal", methods=["GET"])
@require_auth
def get_journal_entries():
    uid = request.uid
    docs = (
        get_db()
        .collection("users").document(uid).collection("journalEntries")
        .order_by("timestamp", direction=firestore.Query.DESCENDING)
        .limit(50)
        .stream()
    )
    return jsonify([serialize_entry(doc) for doc in docs])


@journal_bp.route("/api/journal/<entry_id>", methods=["GET"])
@require_auth
def get_journal_entry(entry_id):
    uid = request.uid
    doc = get_db().collection("users").document(uid).collection("journalEntries").document(entry_id).get()
    if not doc.exists:
        return jsonify({"error": "Not found"}), 404
    return jsonify(serialize_entry(doc))
