from flask import Blueprint, jsonify, request
from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter, Or, And
from auth_middleware import require_auth
from models.serializers import serialize_doc, serialize_value
import datetime

shared_tasks_bp = Blueprint("shared_tasks", __name__)
db = None


def get_db():
    global db
    if db is None:
        db = firestore.client()
    return db


@shared_tasks_bp.route("/api/shared-tasks/<friend_id>", methods=["GET"])
@require_auth
def get_shared_tasks(friend_id):
    uid = request.uid
    db_client = get_db()

    tasks = (
        db_client.collection("shared_tasks")
        .where(
            filter=Or([
                And([FieldFilter("senderId", "==", uid), FieldFilter("receiverId", "==", friend_id)]),
                And([FieldFilter("senderId", "==", friend_id), FieldFilter("receiverId", "==", uid)]),
            ])
        )
        .order_by("createdAt", direction=firestore.Query.DESCENDING)
        .stream()
    )

    return jsonify([serialize_doc(t) for t in tasks])


@shared_tasks_bp.route("/api/shared-tasks", methods=["POST"])
@require_auth
def create_shared_task():
    uid = request.uid
    body = request.get_json() or {}

    receiver_id = body.get("receiverId", "").strip()
    title = body.get("title", "").strip()
    if not receiver_id or not title:
        return jsonify({"error": "receiverId and title are required"}), 400

    subtasks = []
    for st in body.get("subtasks", []):
        subtasks.append({
            "id": st.get("id", ""),
            "title": st.get("title", ""),
            "isDone": st.get("isDone", False),
        })

    due_date_str = body.get("dueDate")
    due_date = None
    if due_date_str:
        try:
            due_date = datetime.datetime.fromisoformat(due_date_str.replace("Z", "+00:00"))
        except ValueError:
            pass

    doc_ref = get_db().collection("shared_tasks").document()
    doc_ref.set({
        "senderId": uid,
        "receiverId": receiver_id,
        "title": title,
        "detail": body.get("detail", ""),
        "dueDate": due_date,
        "isAccepted": False,
        "isCompleted": False,
        "createdAt": firestore.SERVER_TIMESTAMP,
        "completedAt": None,
        "subtasks": subtasks,
    })

    return jsonify({"success": True, "taskId": doc_ref.id}), 201


@shared_tasks_bp.route("/api/shared-tasks/<task_id>/accept", methods=["PATCH"])
@require_auth
def accept_shared_task(task_id):
    uid = request.uid
    db_client = get_db()

    task_ref = db_client.collection("shared_tasks").document(task_id)
    task = task_ref.get()
    if not task.exists:
        return jsonify({"error": "Task not found"}), 404

    data = task.to_dict() or {}
    if data.get("receiverId") != uid:
        return jsonify({"error": "Only the receiver can accept this task"}), 403

    task_ref.update({"isAccepted": True})
    return jsonify({"success": True})


@shared_tasks_bp.route("/api/shared-tasks/<task_id>/complete", methods=["PATCH"])
@require_auth
def complete_shared_task(task_id):
    uid = request.uid
    body = request.get_json() or {}
    is_completed = bool(body.get("isCompleted", False))

    db_client = get_db()
    task_ref = db_client.collection("shared_tasks").document(task_id)
    task = task_ref.get()
    if not task.exists:
        return jsonify({"error": "Task not found"}), 404

    data = task.to_dict() or {}
    if data.get("senderId") != uid and data.get("receiverId") != uid:
        return jsonify({"error": "Not authorized"}), 403

    update_data = {"isCompleted": is_completed}
    if is_completed:
        update_data["completedAt"] = firestore.SERVER_TIMESTAMP
    else:
        update_data["completedAt"] = None

    task_ref.update(update_data)
    return jsonify({"success": True})


@shared_tasks_bp.route("/api/shared-tasks/<task_id>/subtasks", methods=["PATCH"])
@require_auth
def update_subtasks(task_id):
    uid = request.uid
    body = request.get_json() or {}
    subtasks = body.get("subtasks", [])

    db_client = get_db()
    task_ref = db_client.collection("shared_tasks").document(task_id)
    task = task_ref.get()
    if not task.exists:
        return jsonify({"error": "Task not found"}), 404

    data = task.to_dict() or {}
    if data.get("senderId") != uid and data.get("receiverId") != uid:
        return jsonify({"error": "Not authorized"}), 403

    clean_subtasks = [
        {"id": st.get("id", ""), "title": st.get("title", ""), "isDone": bool(st.get("isDone", False))}
        for st in subtasks
    ]
    task_ref.update({"subtasks": clean_subtasks})
    return jsonify({"success": True})


@shared_tasks_bp.route("/api/shared-tasks/<task_id>", methods=["DELETE"])
@require_auth
def delete_shared_task(task_id):
    uid = request.uid
    db_client = get_db()

    task_ref = db_client.collection("shared_tasks").document(task_id)
    task = task_ref.get()
    if not task.exists:
        return jsonify({"error": "Task not found"}), 404

    data = task.to_dict() or {}
    if data.get("senderId") != uid and data.get("receiverId") != uid:
        return jsonify({"error": "Not authorized"}), 403

    task_ref.delete()
    return jsonify({"success": True})
