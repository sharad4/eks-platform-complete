import { useEffect, useState } from "react";

// The frontend calls a RELATIVE url. The ALB routes /api/* to the backend, so the
// same built artifact runs unchanged in dev, staging and production.
export default function App() {
  const [state, setState] = useState({ status: "loading" });

  useEffect(() => {
    const ctrl = new AbortController();
    fetch("/api/ping", { signal: ctrl.signal })
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then((data) => setState({ status: "up", data }))
      .catch((err) => err.name !== "AbortError" && setState({ status: "down", error: err.message }));
    return () => ctrl.abort();
  }, []);

  return (
    <main>
      <h1>EKS Platform</h1>
      <p className="muted">Laravel API + React SPA on Kubernetes, delivered by GitOps.</p>
      <section className={`card ${state.status}`}>
        <strong>Backend</strong>
        {state.status === "loading" && <span>checking…</span>}
        {state.status === "up" && <span>healthy · {state.data.time}</span>}
        {state.status === "down" && <span>unreachable ({state.error})</span>}
      </section>
    </main>
  );
}
