import { useCallback, useEffect, useRef, useState, type ChangeEvent, type ReactElement } from "react";
import { Link, useParams } from "react-router-dom";
import { apiClient } from "../../lib/api-client";
import { useReasonPrompt } from "../../components/prompt";
import { FilePreview } from "../../components/FilePreview";
import { ProviderAvailabilityPanel } from "./ProviderAvailabilityPanel";

interface ProviderDocument {
  id: string;
  type: string;
  status: string;
  rejectionReason?: string;
  fileId?: string;
}

interface ProviderDetail {
  id: string;
  publicName: string;
  email?: string;
  bio?: string;
  experienceYears?: number;
  validationStatus: string;
  documents: ProviderDocument[];
  notes: { id: string; note: string; authorId?: string; createdAt: string }[];
}

// Transitions de statut proposées selon le statut actuel (doit refléter la machine à états du backend).
// "reason: true" = un motif sera demandé avant d'envoyer.
const STATUS_ACTIONS: Record<string, { status: string; label: string; reason: boolean }[]> = {
  pending_review: [
    { status: "approved", label: "Approuver", reason: false },
    { status: "changes_requested", label: "Demander des corrections", reason: true },
    { status: "rejected", label: "Rejeter", reason: true }
  ],
  changes_requested: [{ status: "pending_review", label: "Remettre en revue", reason: false }],
  approved: [{ status: "suspended", label: "Suspendre", reason: true }],
  suspended: [
    { status: "approved", label: "Réactiver", reason: false },
    { status: "rejected", label: "Rejeter", reason: true }
  ],
  rejected: []
};

export function ProviderDetailPage(): ReactElement {
  const { id } = useParams<{ id: string }>();
  const ask = useReasonPrompt(); // ouvre la fenêtre de saisie du motif
  const [provider, setProvider] = useState<ProviderDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  // Identifiant du fichier actuellement affiché dans la fenêtre d'aperçu.
  const [previewFileId, setPreviewFileId] = useState<string | null>(null);
  // Document en cours d'envoi (pour désactiver le bouton pendant l'opération).
  const [uploadingDocId, setUploadingDocId] = useState<string | null>(null);
  // On garde une référence vers chaque champ fichier caché, un par document.
  const fileInputs = useRef<Record<string, HTMLInputElement | null>>({});
  // Texte de la note interne en cours de saisie.
  const [note, setNote] = useState("");

  // useCallback : on garde la même fonction entre les rendus (utile pour useEffect).
  const load = useCallback(() => {
    if (!id) return;
    apiClient
      .get<ProviderDetail>(`/admin/providers/${id}`)
      .then(setProvider)
      .catch(() => setError("Prestataire introuvable."));
  }, [id]);

  useEffect(() => load(), [load]);

  // Approuve un document puis recharge la page.
  async function approveDoc(docId: string): Promise<void> {
    try {
      await apiClient.post(`/admin/verifications/documents/${docId}/approve`, {});
      load();
    } catch {
      setError("L'approbation du document a échoué.");
    }
  }

  // Rejette un document : demande un motif (obligatoire) puis recharge.
  async function rejectDoc(docId: string): Promise<void> {
    const reason = (await ask("Motif du rejet du document ?")) ?? "";
    if (!reason.trim()) return;
    try {
      await apiClient.post(`/admin/verifications/documents/${docId}/reject`, { reason });
      load();
    } catch {
      setError("Le rejet du document a échoué.");
    }
  }

  // Envoie le justificatif choisi et le rattache au document.
  async function uploadDoc(docId: string, event: ChangeEvent<HTMLInputElement>): Promise<void> {
    const file = event.target.files?.[0];
    // On vide le champ tout de suite : sinon rechoisir le MÊME fichier
    // ne déclencherait pas de nouvel événement.
    event.target.value = "";
    if (!file) return;

    setUploadingDocId(docId);
    setError(null);
    try {
      await apiClient.upload(`/admin/verifications/documents/${docId}/file`, file);
      load();
    } catch (uploadError) {
      setError(uploadError instanceof Error ? uploadError.message : "L'envoi du justificatif a échoué.");
    } finally {
      setUploadingDocId(null);
    }
  }

  // Enregistre une note interne sur le prestataire.
  async function submitNote(): Promise<void> {
    if (!note.trim()) return;
    try {
      await apiClient.post(`/admin/providers/${id}/notes`, { note });
      setNote("");
      load();
    } catch (noteError) {
      setError(noteError instanceof Error ? noteError.message : "Enregistrement de la note impossible.");
    }
  }

  // Change le statut du prestataire (demande un motif si l'action l'exige).
  async function changeStatus(status: string, needsReason: boolean): Promise<void> {
    let reason: string | undefined;
    if (needsReason) {
      reason = (await ask("Motif de la décision ?")) ?? "";
      if (!reason.trim()) return;
    }
    try {
      await apiClient.request(`/admin/providers/${id}/status`, {
        method: "PATCH",
        body: JSON.stringify({ status, reason })
      });
      load();
    } catch {
      setError("Le changement de statut a échoué (transition non autorisée ?).");
    }
  }

  if (error) return <p style={{ color: "crimson" }}>{error}</p>;
  if (!provider) return <p>Chargement…</p>;

  const actions = STATUS_ACTIONS[provider.validationStatus] ?? [];

  return (
    <div>
      <p>
        <Link to="/providers">← Retour à la file</Link>
      </p>
      <h1>{provider.publicName}</h1>
      <p style={{ color: "#666" }}>
        {provider.email} — statut : <strong>{provider.validationStatus}</strong>
      </p>
      {provider.bio && <p>{provider.bio}</p>}
      {provider.experienceYears != null && <p>Expérience : {provider.experienceYears} ans</p>}

      <h2>Documents</h2>
      {provider.documents.length === 0 ? (
        <p style={{ color: "#666" }}>Aucun document fourni.</p>
      ) : (
        <table style={{ borderCollapse: "collapse", marginBottom: 24 }}>
          <thead>
            <tr style={{ textAlign: "left", borderBottom: "2px solid #ddd" }}>
              <th style={{ padding: 8 }}>Type</th>
              <th style={{ padding: 8 }}>Justificatif</th>
              <th style={{ padding: 8 }}>Statut</th>
              <th style={{ padding: 8 }}>Motif de rejet</th>
              <th style={{ padding: 8 }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {provider.documents.map((doc) => (
              <tr key={doc.id} style={{ borderBottom: "1px solid #eee" }}>
                <td style={{ padding: 8 }}>{doc.type}</td>
                <td style={{ padding: 8 }}>
                  {doc.fileId ? (
                    <button onClick={() => setPreviewFileId(doc.fileId!)}>Consulter</button>
                  ) : (
                    <span style={{ color: "#a00" }}>aucun fichier</span>
                  )}
                </td>
                <td style={{ padding: 8 }}>{doc.status}</td>
                <td style={{ padding: 8 }}>{doc.rejectionReason ?? "—"}</td>
                <td style={{ padding: 8, display: "flex", gap: 8, flexWrap: "wrap" }}>
                  {/* Le vrai champ fichier est caché : on le déclenche via le bouton
                      ci-dessous, plus lisible qu'un « Parcourir… » brut. */}
                  <input
                    ref={(element) => {
                      fileInputs.current[doc.id] = element;
                    }}
                    type="file"
                    accept="image/jpeg,image/png,image/webp,application/pdf,text/plain,text/csv"
                    style={{ display: "none" }}
                    onChange={(event) => uploadDoc(doc.id, event)}
                  />
                  <button onClick={() => fileInputs.current[doc.id]?.click()} disabled={uploadingDocId === doc.id}>
                    {uploadingDocId === doc.id ? "Envoi…" : doc.fileId ? "Remplacer" : "Joindre"}
                  </button>
                  {/* On ne peut décider que si l'on a pu consulter la pièce. */}
                  <button onClick={() => approveDoc(doc.id)} disabled={!doc.fileId}>
                    Approuver
                  </button>
                  <button onClick={() => rejectDoc(doc.id)} disabled={!doc.fileId}>
                    Rejeter
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {previewFileId && <FilePreview fileId={previewFileId} onClose={() => setPreviewFileId(null)} />}

      {/* Panneau de gestion des disponibilités (US4) */}
      <ProviderAvailabilityPanel providerId={provider.id} />

      <h2>Notes internes</h2>
      <p style={{ color: "#666" }}>Visibles uniquement du back-office, jamais du prestataire.</p>
      {provider.notes.length === 0 ? (
        <p style={{ color: "#666" }}>Aucune note.</p>
      ) : (
        <ul>
          {provider.notes.map((item) => (
            <li key={item.id}>
              {item.note} <span style={{ color: "#888", fontSize: 12 }}>
                ({new Date(item.createdAt).toLocaleString("fr-FR")})
              </span>
            </li>
          ))}
        </ul>
      )}
      <div style={{ display: "flex", gap: 8, marginBottom: 24 }}>
        <input
          value={note}
          onChange={(event) => setNote(event.target.value)}
          placeholder="Ajouter une note interne…"
          style={{ padding: 6, flex: 1 }}
        />
        <button onClick={submitNote} disabled={!note.trim()}>
          Enregistrer
        </button>
      </div>

      <h2>Décision sur le prestataire</h2>
      {actions.length === 0 ? (
        <p style={{ color: "#666" }}>Aucune action possible pour ce statut.</p>
      ) : (
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          {actions.map((action) => (
            <button key={action.status} onClick={() => changeStatus(action.status, action.reason)} style={{ padding: 8 }}>
              {action.label}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
