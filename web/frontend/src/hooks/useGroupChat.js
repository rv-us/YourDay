import { useState, useEffect } from "react";
import { collection, query, orderBy, onSnapshot } from "firebase/firestore";
import { firestoreDb } from "../firebase";

export function useGroupChat(groupId) {
  const [messages, setMessages] = useState([]);

  useEffect(() => {
    if (!groupId) return;

    const q = query(
      collection(firestoreDb, "group_chats", groupId, "messages"),
      orderBy("timestamp", "asc")
    );

    const unsubscribe = onSnapshot(q, (snapshot) => {
      setMessages(snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() })));
    });

    return () => unsubscribe();
  }, [groupId]);

  return messages;
}
