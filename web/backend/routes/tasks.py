from flask import Blueprint, jsonify, request
from firebase_admin import firestore
from auth_middleware import require_auth
from models.serializers import serialize_value
import uuid
import datetime

tasks_bp = Blueprint("tasks", __name__)
db = None


def get_db():
    global db
    if db is None:
        db = firestore.client()
    return db


def serialize_task(doc):
    data = doc.to_dict() or {}
    return {
        "id": doc.id,
        "localTaskId": data.get("localTaskId", doc.id),
        "title": data.get("title", ""),
        "detail": data.get("detail", ""),
        "dueDate": serialize_value(data.get("dueDate")),
        "isDone": data.get("isDone", False),
        "subtasks": serialize_value(data.get("subtasks", [])),
        "completedAt": serialize_value(data.get("completedAt")),
        "origin": data.get("origin", "today"),
        "position": data.get("position", 0),
        "sharedTaskId": data.get("sharedTaskId"),
        "isSharedPending": data.get("isSharedPending", False),
        "proofPostId": data.get("proofPostId"),
        "createdAt": serialize_value(data.get("createdAt")),
        "updatedAt": serialize_value(data.get("updatedAt")),
    }


@tasks_bp.route("/api/tasks", methods=["GET"])
@require_auth
def get_tasks():
    uid = request.uid
    origin = request.args.get("origin")  # "today" or "master"

    query = get_db().collection("users").document(uid).collection("tasks")

    if origin in ("today", "master"):
        query = query.where("origin", "==", origin)

    query = query.order_by("position", direction=firestore.Query.ASCENDING)
    docs = query.stream()
    return jsonify([serialize_task(doc) for doc in docs])


@tasks_bp.route("/api/tasks", methods=["POST"])
@require_auth
def create_task():
    uid = request.uid
    body = request.get_json() or {}

    title = body.get("title", "").strip()
    if not title:
        return jsonify({"error": "title is required"}), 400

    local_task_id = body.get("localTaskId") or str(uuid.uuid4())

    due_date = None
    due_date_str = body.get("dueDate")
    if due_date_str:
        try:
            due_date = datetime.datetime.fromisoformat(due_date_str.replace("Z", "+00:00"))
        except ValueError:
            due_date = datetime.datetime.utcnow()
    else:
        due_date = datetime.datetime.utcnow()

    subtasks = []
    for st in body.get("subtasks", []):
        subtasks.append({
            "id": st.get("id", str(uuid.uuid4())),
            "title": st.get("title", ""),
            "isDone": st.get("isDone", False),
            "completedAt": None,
        })

    task_data = {
        "localTaskId": local_task_id,
        "title": title,
        "detail": body.get("detail", ""),
        "dueDate": due_date,
        "isDone": False,
        "subtasks": subtasks,
        "completedAt": None,
        "origin": body.get("origin", "today"),
        "position": body.get("position", 0),
        "sharedTaskId": None,
        "isSharedPending": False,
        "proofPostId": None,
        "userId": uid,
        "createdAt": firestore.SERVER_TIMESTAMP,
        "updatedAt": firestore.SERVER_TIMESTAMP,
        "schemaVersion": 1,
    }

    doc_ref = get_db().collection("users").document(uid).collection("tasks").document(local_task_id)
    doc_ref.set(task_data)

    return jsonify({"success": True, "localTaskId": local_task_id}), 201


@tasks_bp.route("/api/tasks/<task_id>", methods=["PATCH"])
@require_auth
def update_task(task_id):
    uid = request.uid
    body = request.get_json() or {}

    doc_ref = get_db().collection("users").document(uid).collection("tasks").document(task_id)
    doc = doc_ref.get()
    if not doc.exists:
        return jsonify({"error": "Task not found"}), 404

    update_data = {"updatedAt": firestore.SERVER_TIMESTAMP}

    allowed_fields = ["title", "detail", "isDone", "origin", "position", "subtasks"]
    for field in allowed_fields:
        if field in body:
            update_data[field] = body[field]

    if "dueDate" in body:
        try:
            update_data["dueDate"] = datetime.datetime.fromisoformat(
                body["dueDate"].replace("Z", "+00:00")
            )
        except (ValueError, AttributeError):
            pass

    if "isDone" in body:
        if body["isDone"]:
            update_data["completedAt"] = firestore.SERVER_TIMESTAMP
        else:
            update_data["completedAt"] = None

    doc_ref.update(update_data)
    return jsonify({"success": True})


@tasks_bp.route("/api/tasks/<task_id>", methods=["DELETE"])
@require_auth
def delete_task(task_id):
    uid = request.uid
    get_db().collection("users").document(uid).collection("tasks").document(task_id).delete()
    return jsonify({"success": True})
