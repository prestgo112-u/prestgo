import { createContext, useCallback, useContext, useRef, useState, type ReactElement, type ReactNode } from "react";

// But de ce fichier : remplacer window.prompt (peu fiable dans les navigateurs
// intégrés) par une vraie petite fenêtre de saisie affichée DANS l'application.
//
// On expose une fonction `ask("Question ?")` qui renvoie une promesse :
// - la saisie de l'utilisateur s'il valide,
// - null s'il annule.

type Resolver = (value: string | null) => void;

interface PromptState {
  open: boolean;
  question: string;
}

// Le contexte partage la fonction `ask` à toute l'application.
const PromptContext = createContext<((question: string) => Promise<string | null>) | null>(null);

export function PromptProvider({ children }: { children: ReactNode }): ReactElement {
  const [state, setState] = useState<PromptState>({ open: false, question: "" });
  const [value, setValue] = useState("");
  // On garde la fonction "resolve" de la promesse en cours pour la déclencher au clic.
  const resolverRef = useRef<Resolver | null>(null);

  // Ouvre la fenêtre et renvoie une promesse résolue quand l'utilisateur répond.
  const ask = useCallback((question: string) => {
    setValue("");
    setState({ open: true, question });
    return new Promise<string | null>((resolve) => {
      resolverRef.current = resolve;
    });
  }, []);

  // Ferme la fenêtre en renvoyant la valeur choisie (ou null si annulation).
  function close(result: string | null): void {
    setState({ open: false, question: "" });
    resolverRef.current?.(result);
    resolverRef.current = null;
  }

  return (
    <PromptContext.Provider value={ask}>
      {children}
      {state.open && (
        // Fond semi-transparent qui recouvre la page.
        <div
          style={{
            position: "fixed",
            inset: 0,
            background: "rgba(0,0,0,0.4)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            zIndex: 1000
          }}
        >
          {/* La boîte de dialogue */}
          <div style={{ background: "#fff", padding: 20, borderRadius: 8, width: 400, maxWidth: "90%" }}>
            <p style={{ marginTop: 0, fontWeight: 600 }}>{state.question}</p>
            <textarea
              autoFocus
              value={value}
              onChange={(e) => setValue(e.target.value)}
              rows={3}
              style={{ width: "100%", padding: 8, boxSizing: "border-box" }}
            />
            <div style={{ display: "flex", justifyContent: "flex-end", gap: 8, marginTop: 12 }}>
              <button onClick={() => close(null)}>Annuler</button>
              <button onClick={() => close(value)} style={{ fontWeight: 600 }}>
                Confirmer
              </button>
            </div>
          </div>
        </div>
      )}
    </PromptContext.Provider>
  );
}

// Petit raccourci pour récupérer la fonction `ask` depuis n'importe quel écran.
export function useReasonPrompt(): (question: string) => Promise<string | null> {
  const ask = useContext(PromptContext);
  if (!ask) {
    throw new Error("useReasonPrompt doit être utilisé dans <PromptProvider>");
  }
  return ask;
}
