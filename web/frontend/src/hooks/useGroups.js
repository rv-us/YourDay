import { useState, useEffect } from "react";
import { collection, query, where, orderBy, onSnapshot } from "firebase/firestore";
import { firestoreDb } from "../firebase";

export function useGroups(currentUserId) {
  const [groups, setGroups] = useState([]);

  useEffect(() => {
    if (!currentUserId) return;

    const q = query(
      collection(firestoreDb, "group_chats"),
      where("memberIds", "array-contains", currentUserId),
      orderBy("lastMessageAt", "desc")
    );

    const unsubscribe = onSnapshot(q, (snapshot) => {
      setGroups(snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() })));
    });

    return () => unsubscribe();
  }, [currentUserId]);

  return groups;
}
