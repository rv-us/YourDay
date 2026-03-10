import { useState, useEffect } from "react";
import { collection, query, where, orderBy, onSnapshot, or, and } from "firebase/firestore";
import { firestoreDb } from "../firebase";

export function useChat(friendId, currentUserId) {
  const [messages, setMessages] = useState([]);

  useEffect(() => {
    if (!friendId || !currentUserId) return;

    const q = query(
      collection(firestoreDb, "chat_messages"),
      or(
        and(where("senderId", "==", currentUserId), where("receiverId", "==", friendId)),
        and(where("senderId", "==", friendId), where("receiverId", "==", currentUserId))
      ),
      orderBy("timestamp", "asc")
    );

    const unsubscribe = onSnapshot(q, (snapshot) => {
      const msgs = snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
      setMessages(msgs);
    });

    return () => unsubscribe();
  }, [friendId, currentUserId]);

  return messages;
}
