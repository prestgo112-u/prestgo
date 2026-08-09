import type { ProviderValidationStatus, DocumentStatus } from "@prisma/client";

// Données renvoyées pour un prestataire dans la liste.
export interface ProviderListItem {
  id: string;
  userId: string;
  publicName: string;
  validationStatus: ProviderValidationStatus;
  availabilityStatus: string;
  score: number;
  email?: string;
  createdAt: Date;
}

// Un document du prestataire.
export interface ProviderDocumentDto {
  id: string;
  type: string;
  status: DocumentStatus;
  fileId?: string;
  rejectionReason?: string;
  reviewedBy?: string;
  reviewedAt?: Date;
  createdAt: Date;
}

// Détail complet d'un prestataire (profil + documents + notes internes).
export interface ProviderDetailDto extends ProviderListItem {
  bio?: string;
  experienceYears?: number;
  documents: ProviderDocumentDto[];
  notes: { id: string; note: string; authorId?: string; createdAt: Date }[];
}

// Filtres de recherche de la liste.
export interface ProviderListQuery {
  page?: number;
  limit?: number;
  /** Champ de tri, confronté à une liste blanche côté service (§15.4). */
  sort?: string;
  validationStatus?: ProviderValidationStatus;
  search?: string;
}

// Corps de la requête de changement de statut.
export interface ProviderStatusChangeDto {
  status: ProviderValidationStatus;
  reason?: string;
}

// Champs modifiables par l'admin sur un prestataire.
export interface ProviderUpdateDto {
  publicName?: string;
  bio?: string;
  experienceYears?: number;
  /**
   * Interdit au prestataire de re-soumettre son dossier (§5).
   *
   * Réservé aux cas de fraude avérée : par défaut, un dossier rejeté peut être
   * corrigé et re-présenté, sinon une erreur de pièce jointe condamnerait le
   * compte pour toujours.
   */
  resubmissionBlocked?: boolean;
}