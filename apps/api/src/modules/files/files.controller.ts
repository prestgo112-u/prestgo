import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  ForbiddenException,
  Get,
  NotFoundException,
  Param,
  Post,
  Req,
  Res,
  UploadedFile,
  UseInterceptors
} from "@nestjs/common";
import { FileInterceptor } from "@nestjs/platform-express";
import { ApiTags, ApiOperation, ApiBearerAuth, ApiConsumes, ApiResponse } from "@nestjs/swagger";
import type { Response } from "express";
import { randomUUID } from "node:crypto";
import { extname } from "node:path";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { Public } from "../../common/decorators/public.decorator.js";
import { AuthService } from "../auth/auth.service.js";
import { ok } from "../../common/contracts/api-response.js";
import { ApiEnvelopeResponse, ApiErrorResponse } from "../../common/openapi/api-envelope.decorator.js";
import { FileDto } from "./response-dto.js";
import { canAccessFile, type FileVisibility } from "./file-access.policy.js";
import { FileStorageService } from "./file-storage.service.js";

// Visibilités qu'un appelant a le droit de demander lui-même. On n'y met
// volontairement ni "public" ni "authenticated" : sinon n'importe qui pourrait
// déclarer son propre fichier comme lisible par tous.
const UPLOADABLE_VISIBILITIES = ["restricted", "sensitive"] as const;
type UploadableVisibility = (typeof UPLOADABLE_VISIBILITIES)[number];

// 10 Mo : suffisant pour une pièce d'identité scannée ou une photo.
export const MAX_UPLOAD_BYTES = 10 * 1024 * 1024;

// On n'accepte que des formats de justificatif. Refuser le reste évite de
// stocker des exécutables ou du HTML piégé.
export const ALLOWED_MIME_TYPES = [
  "image/jpeg",
  "image/png",
  "image/webp",
  "application/pdf",
  "text/plain",
  "text/csv"
];

@ApiTags("Files")
@ApiBearerAuth()
@Controller("files")
export class FilesController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: FileStorageService,
    private readonly auth: AuthService
  ) {}

  // POST /files/upload — envoi réel d'un fichier (multipart/form-data).
  // Champ attendu : `file`. Champ optionnel : `visibility`.
  @Post("upload")
  @ApiOperation({ summary: "Upload a file" })
  @ApiConsumes("multipart/form-data")
  @ApiEnvelopeResponse(FileDto, { status: 201, description: "Fichier enregistré" })
  @ApiErrorResponse(400, "Aucun fichier reçu (champ attendu : « file »), ou type de fichier non autorisé")
  @ApiErrorResponse(401, "Authentification requise")
  @ApiErrorResponse(413, "Fichier dépassant 10 Mo")
  @UseInterceptors(FileInterceptor("file", { limits: { fileSize: MAX_UPLOAD_BYTES } }))
  async upload(
    @UploadedFile() upload: Express.Multer.File | undefined,
    @Body() body: { visibility?: string },
    @Req() req: AuthenticatedRequest
  ) {
    if (!upload) {
      throw new BadRequestException("Aucun fichier reçu (champ attendu : « file »)");
    }
    if (!ALLOWED_MIME_TYPES.includes(upload.mimetype)) {
      throw new BadRequestException(`Type de fichier non autorisé : ${upload.mimetype}`);
    }

    // La visibilité est contrôlée : on refuse toute valeur hors de la liste.
    const visibility: UploadableVisibility = UPLOADABLE_VISIBILITIES.includes(body.visibility as UploadableVisibility)
      ? (body.visibility as UploadableVisibility)
      : "restricted";

    // La clé de stockage est TOUJOURS calculée par le serveur. Si le client
    // pouvait la choisir, il pourrait écraser le fichier d'un autre utilisateur
    // ou sortir du dossier de stockage (ex : "../../etc/passwd").
    const originalName = upload.originalname || "sans-nom";
    const storageKey = `uploads/${randomUUID()}${safeExtension(originalName)}`;

    // On écrit le contenu AVANT d'enregistrer la ligne en base : ainsi on ne
    // crée jamais une métadonnée qui pointe vers un fichier inexistant.
    await this.storage.save(storageKey, upload.buffer);

    const file = await this.prisma.file.create({
      data: {
        ownerId: req.user?.id,
        originalName,
        mimeType: upload.mimetype,
        size: upload.size,
        storageKey,
        visibility
      }
    });

    return ok(file, undefined, "Fichier enregistré");
  }

  // GET /files/:id — renvoie les métadonnées si l'utilisateur a le droit d'accès.
  @Get(":id")
  @ApiOperation({ summary: "Get file metadata if authorized" })
  @ApiEnvelopeResponse(FileDto, { description: "Métadonnées du fichier" })
  @ApiErrorResponse(401, "Authentification requise")
  @ApiErrorResponse(403, "Accès au fichier refusé")
  @ApiErrorResponse(404, "Fichier introuvable ou désactivé")
  async getFile(@Param("id") id: string, @Req() req: AuthenticatedRequest) {
    const file = await this.loadAuthorized(id, req);
    return ok(file);
  }

  /**
   * GET /files/:id/content — renvoie le contenu réel du fichier.
   *
   * C'est cette route qui permet à un agent de CONSULTER un justificatif avant
   * de l'approuver, et à l'application mobile d'afficher une photo de profil ou
   * une réalisation de portfolio.
   *
   * `@Public()` : la recherche de prestataires et les fiches publiques sont
   * consultables SANS COMPTE et renvoient `avatarFileId`. Tant que cette route
   * exigeait un jeton, ces identifiants ne menaient à rien pour un visiteur —
   * l'écran d'accueil restait sans aucune image.
   *
   * Ce n'est PAS une ouverture générale : `canAccessFile` reste seul juge, et
   * elle n'autorise l'anonyme que sur la visibilité `public` — celle que le
   * prestataire pose explicitement en publiant un avatar ou un portfolio. Un
   * fichier `restricted` ou `sensitive` reste refusé (403), avec ou sans jeton.
   */
  @Public()
  @Get(":id/content")
  @ApiOperation({ summary: "Download the file content (public files need no token)" })
  // Réponse hors enveloppe : c'est le binaire du fichier, avec son propre
  // Content-Type et `Content-Disposition: inline`.
  @ApiResponse({ status: 200, description: "Contenu binaire du fichier" })
  @ApiErrorResponse(403, "Accès au fichier refusé (fichier non public et demandeur non autorisé)")
  @ApiErrorResponse(404, "Fichier introuvable, désactivé, ou contenu absent du stockage")
  async download(@Param("id") id: string, @Req() req: AuthenticatedRequest, @Res() res: Response) {
    const file = await this.loadAuthorized(id, req, await this.resolveOptionalActor(req));

    let content: Buffer;
    try {
      content = await this.storage.read(file.storageKey);
    } catch {
      throw new NotFoundException("Contenu du fichier introuvable sur le stockage");
    }

    res.setHeader("Content-Type", file.mimeType);
    res.setHeader("Content-Length", content.length);
    // `inline` = le navigateur affiche le document au lieu de le télécharger.
    res.setHeader("Content-Disposition", `inline; filename="${encodeURIComponent(file.originalName)}"`);
    res.send(content);
  }

  // DELETE /files/:id — désactive un fichier (on ne supprime pas : le CDC
  // demande de conserver l'historique). Seul le propriétaire peut le faire.
  @Delete(":id")
  @ApiOperation({ summary: "Disable a file" })
  @ApiEnvelopeResponse(FileDto, { description: "Fichier désactivé (disabledAt renseignée) ; la ligne est conservée" })
  @ApiErrorResponse(401, "Authentification requise")
  @ApiErrorResponse(403, "Seul le propriétaire peut désactiver ce fichier")
  @ApiErrorResponse(404, "Fichier introuvable ou déjà désactivé")
  async disable(@Param("id") id: string, @Req() req: AuthenticatedRequest) {
    const file = await this.loadAuthorized(id, req);
    if (file.ownerId && file.ownerId !== req.user?.id) {
      throw new ForbiddenException("Seul le propriétaire peut désactiver ce fichier");
    }
    const disabled = await this.prisma.file.update({
      where: { id },
      data: { disabledAt: new Date() }
    });
    return ok(disabled, undefined, "Fichier désactivé");
  }

  // Charge un fichier et vérifie les droits d'accès. Factorisé car les trois
  // routes de lecture appliquent exactement la même règle.
  //
  // `actor` n'est fourni que par la route publique, qui résout elle-même le
  // porteur du jeton. Les routes protégées s'appuient sur `req.user`, déjà
  // rempli par la garde globale.
  private async loadAuthorized(id: string, req: AuthenticatedRequest, actor = req.user) {
    const file = await this.prisma.file.findUnique({ where: { id } });
    if (!file || file.disabledAt) {
      throw new NotFoundException("Fichier introuvable");
    }

    const allowed = canAccessFile(
      { visibility: file.visibility as FileVisibility, ownerId: file.ownerId },
      actor
    );
    if (!allowed) {
      throw new ForbiddenException("Accès au fichier refusé");
    }

    return file;
  }

  /**
   * Identité du demandeur sur une route `@Public()`.
   *
   * La garde globale sort AVANT de remplir `request.user` quand la route est
   * publique : sans cette résolution, le propriétaire d'un justificatif se
   * verrait refuser son propre fichier. On relit donc l'en-tête nous-mêmes.
   *
   * Un jeton absent, expiré ou invalide ne provoque PAS de 401 : le demandeur
   * est simplement traité comme anonyme, et n'obtiendra que les fichiers
   * `public`. C'est le comportement voulu pour une balise `<img>` — un jeton
   * périmé en cours de défilement ne doit pas casser l'affichage des avatars,
   * qui sont publics de toute façon.
   */
  private async resolveOptionalActor(req: AuthenticatedRequest): Promise<AuthenticatedRequest["user"]> {
    if (req.user) {
      return req.user;
    }

    const [scheme, token] = (req.headers?.authorization as string | undefined)?.split(" ") ?? [];
    if (scheme !== "Bearer" || !token) {
      return undefined;
    }

    try {
      const payload = await this.auth.verifyAccessToken(token);
      return { id: payload.sub, roles: payload.roles, permissions: payload.permissions, sessionId: payload.sid };
    } catch {
      return undefined;
    }
  }
}

// Garde uniquement une extension simple (lettres/chiffres) pour la clé de stockage.
function safeExtension(originalName: string): string {
  const extension = extname(originalName).toLowerCase();
  return /^\.[a-z0-9]{1,10}$/.test(extension) ? extension : "";
}
