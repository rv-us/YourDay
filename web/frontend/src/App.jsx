import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { AuthProvider } from "./context/AuthContext";
import ProtectedRoute from "./components/layout/ProtectedRoute";
import Navbar from "./components/layout/Navbar";
import LoginPage from "./pages/LoginPage";
import DashboardPage from "./pages/DashboardPage";
import TasksPage from "./pages/TasksPage";
import ProfilePage from "./pages/ProfilePage";
import GardenPage from "./pages/GardenPage";
import CalendarPage from "./pages/CalendarPage";
import LeaderboardPage from "./pages/LeaderboardPage";
import SocialPage from "./pages/SocialPage";
import ChatListPage from "./pages/ChatListPage";
import ChatDetailPage from "./pages/ChatDetailPage";
import GroupChatPage from "./pages/GroupChatPage";
import NotesPage from "./pages/NotesPage";
import JournalPage from "./pages/JournalPage";
import NotFoundPage from "./pages/NotFoundPage";

function AppLayout({ children }) {
  return (
    <div className="app-shell">
      <Navbar />
      {children}
    </div>
  );
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route
            path="/*"
            element={
              <ProtectedRoute>
                <AppLayout>
                  <Routes>
                    <Route path="/" element={<Navigate to="/dashboard" replace />} />
                    <Route path="/dashboard" element={<DashboardPage />} />
                    <Route path="/tasks" element={<TasksPage />} />
                    <Route path="/profile" element={<ProfilePage />} />
                    <Route path="/garden" element={<GardenPage />} />
                    <Route path="/calendar" element={<CalendarPage />} />
                    <Route path="/leaderboard" element={<LeaderboardPage />} />
                    <Route path="/social" element={<SocialPage />} />
                    <Route path="/chat" element={<ChatListPage />} />
                    <Route path="/chat/:friendId" element={<ChatDetailPage />} />
                    <Route path="/group/:groupId" element={<GroupChatPage />} />
                    <Route path="/notes" element={<NotesPage />} />
                    <Route path="/journal" element={<JournalPage />} />
                    <Route path="*" element={<NotFoundPage />} />
                  </Routes>
                </AppLayout>
              </ProtectedRoute>
            }
          />
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  );
}
