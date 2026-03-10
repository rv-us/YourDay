import { useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  createUserWithEmailAndPassword,
  signInWithEmailAndPassword,
  updateProfile,
} from "firebase/auth";
import { auth } from "../firebase";

export default function LoginPage() {
  const navigate = useNavigate();
  const [mode, setMode] = useState("signin");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (event) => {
    event.preventDefault();
    setError("");
    setLoading(true);

    try {
      if (mode === "register") {
        const credential = await createUserWithEmailAndPassword(auth, email, password);
        if (displayName.trim()) {
          await updateProfile(credential.user, { displayName: displayName.trim() });
        }
      } else {
        await signInWithEmailAndPassword(auth, email, password);
      }
      navigate("/dashboard");
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="auth-shell">
      <div className="auth-layout">
        <section className="auth-showcase">
          <div className="stack">
            <h1 className="page-title page-title--serif">Plan. Finish. Grow.</h1>
          </div>

          <div className="auth-showcase__grid">
            <div className="metric-card">
              <div className="metric-label">Tasks</div>
              <div className="metric-value" style={{ fontSize: "1.4rem" }}>
                Tight boards
              </div>
            </div>
            <div className="metric-card">
              <div className="metric-label">Garden</div>
              <div className="metric-value" style={{ fontSize: "1.4rem" }}>
                Visible rewards
              </div>
            </div>
            <div className="metric-card">
              <div className="metric-label">Social</div>
              <div className="metric-value" style={{ fontSize: "1.4rem" }}>
                Shared momentum
              </div>
            </div>
            <div className="metric-card">
              <div className="metric-label">Notes</div>
              <div className="metric-value" style={{ fontSize: "1.4rem" }}>
                Workspace memory
              </div>
            </div>
          </div>
        </section>

        <section className="auth-card">
          <div className="auth-card__header">
            <div className="auth-brand">
              <span className="auth-brand__mark" aria-hidden="true">
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M12 3C12 3 7.5 7.3 7.5 11.2A4.5 4.5 0 0 0 12 15.7A4.5 4.5 0 0 0 16.5 11.2C16.5 7.3 12 3 12 3Z" />
                  <path d="M6 21C6 17.5 8.8 15.2 12 12.9C15.2 15.2 18 17.5 18 21" />
                </svg>
              </span>
              <div>
                <div className="auth-brand__title">YourDay</div>
                <div className="auth-brand__copy">Sign in</div>
              </div>
            </div>
          </div>

          <div className="stack">
            <div className="segmented-control">
              {[
                ["signin", "Sign In"],
                ["register", "Create Account"],
              ].map(([value, label]) => (
                <button
                  key={value}
                  type="button"
                  className={`segmented-control__button${mode === value ? " segmented-control__button--active" : ""}`}
                  onClick={() => setMode(value)}
                >
                  {label}
                </button>
              ))}
            </div>

            <form onSubmit={handleSubmit} className="stack">
              {mode === "register" && (
                <div className="form-field">
                  <label className="form-label">Display Name</label>
                  <input
                    type="text"
                    value={displayName}
                    onChange={(event) => setDisplayName(event.target.value)}
                    placeholder="Your in-app name"
                  />
                </div>
              )}

              <div className="form-field">
                <label className="form-label">Email</label>
                <input
                  type="email"
                  value={email}
                  onChange={(event) => setEmail(event.target.value)}
                  required
                  placeholder="you@example.com"
                />
              </div>

              <div className="form-field">
                <label className="form-label">Password</label>
                <input
                  type="password"
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                  required
                  placeholder="Enter your password"
                />
              </div>

              {error && <div className="error-banner">{error}</div>}

              <button type="submit" className="btn btn-primary" disabled={loading} style={{ width: "100%" }}>
                {loading ? "Loading..." : mode === "register" ? "Create Account" : "Sign In"}
              </button>
            </form>
          </div>
        </section>
      </div>
    </div>
  );
}
