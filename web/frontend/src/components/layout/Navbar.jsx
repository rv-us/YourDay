import { Link, useLocation, useNavigate } from "react-router-dom";
import { signOut } from "firebase/auth";
import { auth } from "../../firebase";
import { useAuth } from "../../context/AuthContext";

const PRIMARY_TABS = [
  {
    to: "/tasks",
    label: "Tasks",
    icon: (
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
        <path d="M9 11L12 14L22 4" />
        <path d="M21 12V19C21 20.1 20.1 21 19 21H5C3.9 21 3 20.1 3 19V5C3 3.9 3.9 3 5 3H16" />
      </svg>
    ),
  },
  {
    to: "/garden",
    label: "Garden",
    icon: (
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
        <path d="M6 21C6 17 9 14 12 11C15 14 18 17 18 21" />
        <path d="M12 3C12 3 8 7 8 11C8 13.2 9.8 15 12 15C14.2 15 16 13.2 16 11C16 7 12 3 12 3Z" />
      </svg>
    ),
  },
  {
    to: "/dashboard",
    label: "Dashboard",
    icon: (
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
        <rect x="3" y="3" width="7" height="7" rx="1" />
        <rect x="14" y="3" width="7" height="7" rx="1" />
        <rect x="3" y="14" width="7" height="7" rx="1" />
        <rect x="14" y="14" width="7" height="7" rx="1" />
      </svg>
    ),
  },
];

const SOCIAL_LINKS = [
  { to: "/social", label: "Friends" },
  { to: "/leaderboard", label: "Leaderboard" },
  { to: "/chat", label: "Chat" },
];

const MORE_LINKS = [
  { to: "/notes", label: "Notes" },
  { to: "/journal", label: "Journal" },
  { to: "/profile", label: "Settings" },
];

export default function Navbar() {
  const location = useLocation();
  const navigate = useNavigate();
  const { user } = useAuth();

  const handleSignOut = async () => {
    await signOut(auth);
    navigate("/login");
  };

  const displayName = user?.displayName || user?.email?.split("@")[0] || "Gardener";
  const initials = displayName.slice(0, 2).toUpperCase();

  return (
    <nav className="topbar">
      <div className="topbar__inner">
        <div className="topbar__main">
          <Link to="/dashboard" className="topbar__brand">
            <span className="topbar__brand-mark" aria-hidden="true">
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                <path d="M12 3C12 3 7.5 7.3 7.5 11.2A4.5 4.5 0 0 0 12 15.7A4.5 4.5 0 0 0 16.5 11.2C16.5 7.3 12 3 12 3Z" />
                <path d="M6 21C6 17.5 8.8 15.2 12 12.9C15.2 15.2 18 17.5 18 21" />
              </svg>
            </span>
            <span className="topbar__brand-copy">
              <span className="topbar__eyebrow">Garden Workspace</span>
              <span className="topbar__title">YourDay</span>
              <span className="topbar__subtitle">Task management with a cultivated edge</span>
            </span>
          </Link>

          <div className="topbar__meta">
            <div className="user-chip">
              <span className="user-chip__avatar">{initials}</span>
              <span>{displayName}</span>
            </div>
            {user && (
              <button className="btn btn-ghost btn-sm" onClick={handleSignOut}>
                Sign Out
              </button>
            )}
          </div>
        </div>

        <div className="topbar__nav">
          <div className="nav-cluster">
            <span className="nav-cluster__label">Core</span>
            {PRIMARY_TABS.map((tab) => {
              const active = location.pathname.startsWith(tab.to);
              return (
                <Link key={tab.to} to={tab.to} className={`nav-chip${active ? " nav-chip--active" : ""}`}>
                  {tab.icon}
                  {tab.label}
                </Link>
              );
            })}
          </div>

          <div className="nav-cluster">
            <span className="nav-cluster__label">Connect</span>
            {SOCIAL_LINKS.map((link) => {
              const active = location.pathname.startsWith(link.to);
              return (
                <Link key={link.to} to={link.to} className={`nav-chip${active ? " nav-chip--active" : ""}`}>
                  {link.label}
                </Link>
              );
            })}
          </div>

          <div className="nav-cluster">
            <span className="nav-cluster__label">Workspace</span>
            {MORE_LINKS.map((link) => {
              const active = location.pathname.startsWith(link.to);
              return (
                <Link key={link.to} to={link.to} className={`nav-chip${active ? " nav-chip--active" : ""}`}>
                  {link.label}
                </Link>
              );
            })}
          </div>
        </div>
      </div>
    </nav>
  );
}
