/**
 * Checklist de complétude d'un dossier prestataire (§5).
 *
 * C'est le contrat affiché dans l'application : cinq cases, toutes vertes avant
 * de pouvoir soumettre. Le calcul est isolé ici parce qu'il sert à deux
 * endroits — l'affichage (`GET /providers/me`) et le refus de soumission
 * (`POST /providers/me/submit`). Les faire diverger produirait le pire des
 * défauts : une checklist toute verte et un bouton qui refuse.
 */
export interface ProviderChecklist {
  profile: boolean;
  services: boolean;
  zones: boolean;
  availabilities: boolean;
  documents: boolean;
}

export interface ChecklistInput {
  publicName: string;
  bio: string | null;
  /** Services actifs disposant d'au moins une formule active. */
  bookableServices: number;
  zones: number;
  availabilities: number;
  /** Types de justificatifs exigés par le réglage `provider.required_document_types`. */
  requiredDocumentTypes: string[];
  /** Types pour lesquels un justificatif exploitable a déjà été fourni. */
  providedDocumentTypes: string[];
}

export function buildChecklist(input: ChecklistInput): ProviderChecklist {
  return {
    // Un nom public et une présentation : c'est le strict minimum pour qu'un
    // client sache à qui il a affaire avant de réserver.
    profile: input.publicName.trim().length > 0 && (input.bio?.trim().length ?? 0) > 0,
    // « Service » vaut ici « service VENDABLE ». Un service sans formule active
    // n'a ni prix ni durée : il ne peut pas être réservé, la case ne doit donc
    // pas être verte.
    services: input.bookableServices > 0,
    zones: input.zones > 0,
    availabilities: input.availabilities > 0,
    documents: input.requiredDocumentTypes.every((type) => input.providedDocumentTypes.includes(type))
  };
}

export function isChecklistComplete(checklist: ProviderChecklist): boolean {
  return Object.values(checklist).every(Boolean);
}

/**
 * Traduit une checklist incomplète en liste d'erreurs exploitable.
 *
 * Le §5 demande que la checklist figure dans `errors` quand la soumission est
 * refusée : sans cela, le prestataire reçoit « dossier incomplet » sans savoir
 * quoi corriger.
 */
export function checklistErrors(checklist: ProviderChecklist): { field: string; code: string; message: string }[] {
  const messages: Record<keyof ProviderChecklist, string> = {
    profile: "Complétez votre nom public et votre présentation",
    services: "Déclarez au moins un service avec une formule tarifaire active",
    zones: "Choisissez au moins une zone d'intervention",
    availabilities: "Renseignez vos disponibilités hebdomadaires",
    documents: "Fournissez tous les justificatifs obligatoires"
  };

  return (Object.keys(messages) as (keyof ProviderChecklist)[])
    .filter((key) => !checklist[key])
    .map((key) => ({ field: key, code: "checklist_incomplete", message: messages[key] }));
}
