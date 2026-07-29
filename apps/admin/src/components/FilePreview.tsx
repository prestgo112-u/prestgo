import { useEffect, useState, type ReactElement } from "react";
import { apiClient } from "../lib/api-client";

interface FilePreviewProps {
  fileId: string;
  onClose: () => void;
}

/**
 * Affiche le contenu d'un fichier protégé (justificatif, export...).
 *
 * Le fichier n'est pas accessible par une simple URL : il faut présenter le
 * token. On récupère donc son contenu, on en fait une URL temporaire locale,
 * puis on l'affiche selon son type (image, PDF, ou texte).
 */
export function FilePreview({ fileId, onClose }: FilePreviewProps): ReactElement {
  const [url, setUrl] = useState<string | null>(null);
  const [mimeType, setMimeType] = useState<string>("");
  const [name, setName] = useState<string>("");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let objectUrl: string | null = null;
    let cancelled = false;

    async function load(): Promise<void> {
      try {
        // 1) les métadonnées, pour connaître le type et le nom du fichier
        const meta = await apiClient.get<{ originalName: string; mimeType: string }>(`/files/${fileId}`);
        // 2) le contenu réel
        const blobUrl = await apiClient.fetchBlobUrl(`/files/${fileId}/content`);
        if (cancelled) {
          URL.revokeObjectURL(blobUrl);
          return;
        }
        objectUrl = blobUrl;
        setMimeType(meta.mimeType);
        setName(meta.originalName);
        setUrl(blobUrl);
      } catch (loadError) {
        if (!cancelled) {
          setError(loadError instanceof Error ? loadError.message : "Fichier inaccessible.");
        }
      }
    }

    void load();

    // Nettoyage : on libère la mémoire prise par l'URL temporaire.
    return () => {
      cancelled = true;
      if (objectUrl) {
        URL.revokeObjectURL(objectUrl);
      }
    };
  }, [fileId]);

  return (
    <div
      onClick={onClose}
      style={{
        position: "fixed",
        inset: 0,
        background: "rgba(0,0,0,0.55)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        padding: 24,
        zIndex: 1000
      }}
    >
      {/* stopPropagation : cliquer DANS la fenêtre ne doit pas la fermer */}
      <div
        onClick={(event) => event.stopPropagation()}
        style={{ background: "#fff", padding: 16, borderRadius: 6, maxWidth: "90vw", maxHeight: "90vh", overflow: "auto" }}
      >
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 16, marginBottom: 12 }}>
          <strong>{name || "Document"}</strong>
          <span style={{ display: "flex", gap: 8 }}>
            {url && (
              <a href={url} download={name} style={{ padding: "4px 8px" }}>
                Télécharger
              </a>
            )}
            <button onClick={onClose}>Fermer</button>
          </span>
        </div>

        {error && <p style={{ color: "crimson" }}>{error}</p>}
        {!url && !error && <p>Chargement du document…</p>}

        {url && mimeType.startsWith("image/") && (
          <img src={url} alt={name} style={{ maxWidth: "80vw", maxHeight: "70vh" }} />
        )}
        {url && mimeType === "application/pdf" && (
          <iframe src={url} title={name} style={{ width: "80vw", height: "70vh", border: "1px solid #ddd" }} />
        )}
        {url && !mimeType.startsWith("image/") && mimeType !== "application/pdf" && (
          <iframe src={url} title={name} style={{ width: "70vw", height: "60vh", border: "1px solid #ddd" }} />
        )}
      </div>
    </div>
  );
}
