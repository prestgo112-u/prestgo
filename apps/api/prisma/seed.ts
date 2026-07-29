import { PrismaClient } from "@prisma/client";
import { randomUUID } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { hashPassword } from "../src/common/security/password.js";

const prisma = new PrismaClient();

// Même dossier racine que le FileStorageService de l'API.
const STORAGE_ROOT = resolve(process.env.FILE_STORAGE_DIR ?? "storage");

/**
 * Crée un justificatif de démonstration : un vrai fichier sur le disque + sa
 * ligne de métadonnées en base. Sans ça, la fiche prestataire afficherait
 * « aucun fichier » et les boutons Approuver/Rejeter resteraient inactifs.
 */
async function createDemoFile(ownerId: string, providerId: string, publicName: string, docType: string) {
  const storageKey = `documents/${providerId}/${randomUUID()}.txt`;
  const content = Buffer.from(
    [
      "JUSTIFICATIF DE DÉMONSTRATION — PRESTGO",
      "",
      `Prestataire : ${publicName}`,
      `Type de document : ${docType}`,
      `Référence : DEMO-${randomUUID().slice(0, 8).toUpperCase()}`,
      "",
      "Ce fichier est généré par le seed pour permettre de tester la",
      "consultation des documents dans le back-office.",
      ""
    ].join("\n"),
    "utf8"
  );

  const target = join(STORAGE_ROOT, storageKey);
  await mkdir(dirname(target), { recursive: true });
  await writeFile(target, content);

  return prisma.file.create({
    data: {
      ownerId,
      originalName: `${docType}-demo.txt`,
      mimeType: "text/plain",
      size: content.length,
      storageKey,
      visibility: "sensitive"
    }
  });
}

// Mot de passe par défaut du super admin de démonstration.
// À CHANGER après la première connexion (ne jamais utiliser tel quel en production).
const SUPER_ADMIN_EMAIL = "admin@prestgo.test";
const SUPER_ADMIN_PASSWORD = "prestgo123!";

const roleSeeds = [
  { code: "super_admin", name: "Super admin", description: "Full platform administration" },
  { code: "admin", name: "Admin", description: "Operational administration" },
  { code: "agent_support", name: "Agent support", description: "Support operations" },
  { code: "agent_validation", name: "Agent validation", description: "Provider validation" },
  { code: "moderator", name: "Moderator", description: "Review and content moderation" },
  { code: "read_only", name: "Read only", description: "Read-only administration" }
];

const permissionSeeds = [
  ["admin.dashboard.read", "admin.dashboard", "read"],
  ["admin.users.read", "admin.users", "read"],
  ["admin.users.status.update", "admin.users", "status.update"],
  ["admin.roles.manage", "admin.roles", "manage"],
  ["audit.read", "audit", "read"],
  ["files.sensitive.read", "files", "sensitive.read"],
  // Lot 0 : lire un fichier "restreint" appartenant à quelqu'un d'autre.
  // Sans cette permission, on ne voit que ses propres fichiers restreints.
  ["files.any.read", "files", "any.read"],
  // Permissions Lot 2 (écran Clients)
  ["admin.clients.read", "admin.clients", "read"],
  ["admin.clients.notes", "admin.clients", "notes"],
  // Permissions US2 (validation des prestataires)
  ["admin.providers.read", "admin.providers", "read"],
  ["admin.providers.update", "admin.providers", "update"],
  ["admin.providers.status.update", "admin.providers", "status.update"],
  ["admin.verifications.documents.review", "admin.verifications", "documents.review"],
  // Permissions US3 (missions, messages, avis, litiges)
  ["admin.missions.read", "admin.missions", "read"],
  ["admin.missions.manage", "admin.missions", "manage"],
  ["admin.messages.read", "admin.messages", "read"],
  ["admin.reviews.read", "admin.reviews", "read"],
  ["admin.reviews.moderate", "admin.reviews", "moderate"],
  ["admin.disputes.read", "admin.disputes", "read"],
  ["admin.disputes.manage", "admin.disputes", "manage"],
  // Permissions US4 (catalogue, zones, disponibilités)
  ["admin.catalog.read", "admin.catalog", "read"],
  ["admin.catalog.manage", "admin.catalog", "manage"],
  ["admin.zones.read", "admin.zones", "read"],
  ["admin.zones.manage", "admin.zones", "manage"],
  ["admin.availability.read", "admin.availability", "read"],
  ["admin.availability.manage", "admin.availability", "manage"],
  // Permissions US5 (réglages, notifications, exports)
  ["admin.settings.read", "admin.settings", "read"],
  ["admin.settings.update", "admin.settings", "update"],
  ["admin.notifications.read", "admin.notifications", "read"],
  ["admin.notifications.send", "admin.notifications", "send"],
  ["admin.exports.manage", "admin.exports", "manage"]
] as const;

// Prestataires de démonstration (avec quelques documents à examiner).
const providerSeeds = [
  {
    email: "kofi.plombier@prestgo.test",
    firstName: "Kofi",
    lastName: "Yao",
    publicName: "Kofi Plomberie",
    bio: "Plombier avec 8 ans d'expérience.",
    experienceYears: 8,
    documents: [
      { type: "identity" },
      { type: "insurance" }
    ]
  },
  {
    email: "ama.electricite@prestgo.test",
    firstName: "Ama",
    lastName: "Koné",
    publicName: "Ama Électricité",
    bio: "Électricienne certifiée.",
    experienceYears: 5,
    documents: [{ type: "identity" }]
  }
];

async function main(): Promise<void> {
  for (const [code, module, action] of permissionSeeds) {
    await prisma.permission.upsert({
      where: { code },
      update: {},
      create: { code, module, action, description: code }
    });
  }

  for (const role of roleSeeds) {
    await prisma.role.upsert({
      where: { code: role.code },
      update: role,
      create: { ...role, isSystem: true }
    });
  }

  // On hache le mot de passe avant de l'enregistrer (jamais en clair).
  const passwordHash = await hashPassword(SUPER_ADMIN_PASSWORD);

  const superAdmin = await prisma.user.upsert({
    where: { email: SUPER_ADMIN_EMAIL },
    update: { status: "active", passwordHash },
    create: {
      email: SUPER_ADMIN_EMAIL,
      firstName: "PRESTGO",
      lastName: "Admin",
      passwordHash,
      status: "active"
    }
  });

  const superAdminRole = await prisma.role.findUniqueOrThrow({ where: { code: "super_admin" } });

  // On donne TOUTES les permissions au rôle super_admin (sinon il ne peut rien faire).
  const allPermissions = await prisma.permission.findMany();
  for (const permission of allPermissions) {
    await prisma.rolePermission.upsert({
      where: { roleId_permissionId: { roleId: superAdminRole.id, permissionId: permission.id } },
      update: {},
      create: { roleId: superAdminRole.id, permissionId: permission.id }
    });
  }

  // On relie l'utilisateur super admin à son rôle.
  await prisma.userRole.upsert({
    where: { userId_roleId: { userId: superAdmin.id, roleId: superAdminRole.id } },
    update: {},
    create: { userId: superAdmin.id, roleId: superAdminRole.id }
  });

  // On donne aussi les permissions de validation au rôle "agent_validation".
  const validationRole = await prisma.role.findUniqueOrThrow({ where: { code: "agent_validation" } });
  const validationPerms = await prisma.permission.findMany({
    where: {
      code: {
        in: [
          "admin.dashboard.read",
          "admin.providers.read",
          "admin.providers.status.update",
          "admin.verifications.documents.review",
          // Sans ce droit, un agent de validation ne pourrait pas OUVRIR les
          // justificatifs qu'il doit justement examiner.
          "files.sensitive.read"
        ]
      }
    }
  });
  for (const permission of validationPerms) {
    await prisma.rolePermission.upsert({
      where: { roleId_permissionId: { roleId: validationRole.id, permissionId: permission.id } },
      update: {},
      create: { roleId: validationRole.id, permissionId: permission.id }
    });
  }

  // Prestataires de démonstration : compte utilisateur + profil "pending_review" + documents.
  const providerHash = await hashPassword("prestgo123!");
  for (const seed of providerSeeds) {
    const user = await prisma.user.upsert({
      where: { email: seed.email },
      update: { status: "active" },
      create: {
        email: seed.email,
        firstName: seed.firstName,
        lastName: seed.lastName,
        passwordHash: providerHash,
        status: "active"
      }
    });

    const profile = await prisma.providerProfile.upsert({
      where: { userId: user.id },
      update: { validationStatus: "pending_review" },
      create: {
        userId: user.id,
        publicName: seed.publicName,
        bio: seed.bio,
        experienceYears: seed.experienceYears,
        validationStatus: "pending_review"
      }
    });

    // Documents de vérification.
    //
    // Le seed doit pouvoir être relancé sans rien dupliquer, MAIS aussi rattraper
    // ce qui manque sur une base plus ancienne. On travaille donc type par type :
    // on crée le document s'il n'existe pas, et on lui joint un justificatif de
    // démonstration s'il n'en a pas encore.
    for (const doc of seed.documents) {
      const existing = await prisma.providerDocument.findFirst({
        where: { providerId: profile.id, type: doc.type }
      });

      if (!existing) {
        const file = await createDemoFile(user.id, profile.id, seed.publicName, doc.type);
        await prisma.providerDocument.create({
          data: { providerId: profile.id, type: doc.type, status: "pending", fileId: file.id }
        });
      } else if (!existing.fileId) {
        // Document créé avant le Lot 1 : sans fichier joint, l'agent n'aurait
        // rien à consulter avant d'approuver ou de rejeter.
        const file = await createDemoFile(user.id, profile.id, seed.publicName, doc.type);
        await prisma.providerDocument.update({
          where: { id: existing.id },
          data: { fileId: file.id }
        });
      }
    }
  }

  // === Données de démonstration US3 : une mission complète (fil, avis, litige) ===
  // On crée un client, puis une mission entre ce client et le prestataire Kofi.
  const clientUser = await prisma.user.upsert({
    where: { email: "client.demo@prestgo.test" },
    update: { status: "active" },
    create: {
      email: "client.demo@prestgo.test",
      firstName: "Awa",
      lastName: "Client",
      passwordHash: providerHash,
      status: "active"
    }
  });

  const kofi = await prisma.providerProfile.findFirst({ where: { user: { email: "kofi.plombier@prestgo.test" } } });

  // Catalogue de démonstration : catégorie → type de service → prestation vendable.
  // Il est créé AVANT la mission, car depuis le Lot 1 une mission pointe vers
  // la prestation (son titre, son prix, sa durée).
  const category = await prisma.catalogCategory.upsert({
    where: { slug: "plomberie" },
    update: {},
    create: { name: "Plomberie", slug: "plomberie", description: "Services de plomberie", displayOrder: 1 }
  });

  const serviceType = await prisma.serviceType.upsert({
    where: { slug: "reparation-fuite" },
    update: {},
    create: { categoryId: category.id, name: "Réparation de fuite", slug: "reparation-fuite" }
  });

  // Prestation proposée par Kofi + sa formule tarifaire.
  let demoPackId: string | undefined;
  if (kofi) {
    let providerService = await prisma.providerService.findFirst({
      where: { providerId: kofi.id, serviceTypeId: serviceType.id }
    });
    if (!providerService) {
      providerService = await prisma.providerService.create({
        data: {
          providerId: kofi.id,
          serviceTypeId: serviceType.id,
          title: "Dépannage plomberie à domicile",
          description: "Diagnostic et réparation des fuites courantes."
        }
      });
    }

    let pack = await prisma.servicePack.findFirst({ where: { providerServiceId: providerService.id } });
    if (!pack) {
      pack = await prisma.servicePack.create({
        data: {
          providerServiceId: providerService.id,
          title: "Réparation de fuite simple",
          description: "Intervention d'une heure, petites fournitures incluses.",
          price: 15000,
          durationMinutes: 60
        }
      });
    }
    demoPackId = pack.id;
  }

  // Adresse d'intervention du client.
  let clientAddress = await prisma.address.findFirst({ where: { userId: clientUser.id } });
  if (!clientAddress) {
    clientAddress = await prisma.address.create({
      data: {
        userId: clientUser.id,
        label: "Domicile",
        city: "Abidjan",
        commune: "Cocody",
        details: "Rue des Jardins, villa 12",
        latitude: 5.35,
        longitude: -3.98,
        isDefault: true
      }
    });
  }

  // Rattrapage : une mission créée avant le Lot 1 n'a ni prestation ni adresse
  // (les colonnes n'existaient pas encore). On complète ces missions au lieu de
  // les laisser incomplètes pour toujours.
  // On se limite aux missions DU CLIENT DE DÉMONSTRATION : l'adresse ci-dessus
  // lui appartient, il serait faux de la rattacher à la mission de quelqu'un d'autre.
  const incompleteMissions = await prisma.mission.findMany({
    where: { clientId: clientUser.id, OR: [{ packId: null }, { addressId: null }] }
  });
  for (const mission of incompleteMissions) {
    await prisma.mission.update({
      where: { id: mission.id },
      data: {
        packId: mission.packId ?? demoPackId,
        addressId: mission.addressId ?? clientAddress.id,
        scheduledAt: mission.scheduledAt ?? new Date("2026-08-03T14:00:00Z")
      }
    });
  }

  // On ne recrée la mission de démo que si aucune n'existe (seed ré-exécutable).
  const missionCount = await prisma.mission.count();
  if (missionCount === 0) {
    const mission = await prisma.mission.create({
      data: {
        clientId: clientUser.id,
        providerId: kofi?.id ?? null,
        packId: demoPackId,
        addressId: clientAddress.id,
        scheduledAt: new Date("2026-08-03T14:00:00Z"),
        status: "confirmed",
        instructions: "Fuite sous l'évier de la cuisine.",
        history: { create: { newStatus: "confirmed", reason: "Confirmée par le prestataire" } }
      }
    });

    // Un fil de discussion avec 2 messages.
    await prisma.chatThread.create({
      data: {
        missionId: mission.id,
        messages: {
          create: [
            { senderId: clientUser.id, message: "Bonjour, à quelle heure passez-vous ?" },
            { senderId: kofi?.userId ?? null, message: "Bonjour, vers 14h si cela vous convient." }
          ]
        }
      }
    });

    // Un avis signalé (à modérer).
    await prisma.review.create({
      data: {
        missionId: mission.id,
        authorId: clientUser.id,
        rating: 2,
        comment: "Travail correct mais retard important.",
        status: "reported",
        reports: { create: { reportedBy: kofi?.userId ?? null, reason: "Commentaire jugé injuste" } }
      }
    });

    // Un litige ouvert sur cette mission.
    await prisma.dispute.create({
      data: {
        missionId: mission.id,
        openedBy: clientUser.id,
        reason: "Prestation incomplète",
        description: "La fuite persiste après l'intervention.",
        status: "open"
      }
    });
  }

  // === Données de démonstration US4 : zone et disponibilité ===
  // (le catalogue est créé plus haut, car la mission de démo s'appuie dessus)

  // Villes de couverture (Lot 4 : `Zone.cityId` pointe maintenant vers une
  // vraie table, plus vers un texte libre).
  const abidjan = await prisma.city.upsert({
    where: { slug: "abidjan" },
    update: {},
    create: { name: "Abidjan", slug: "abidjan", countryCode: "CI" }
  });
  await prisma.city.upsert({
    where: { slug: "yamoussoukro" },
    update: {},
    create: { name: "Yamoussoukro", slug: "yamoussoukro", countryCode: "CI" }
  });

  // Une zone active de démonstration (coordonnées simples, sans PostGIS).
  const zoneCount = await prisma.zone.count();
  if (zoneCount === 0) {
    await prisma.zone.create({
      data: { name: "Cocody", cityId: abidjan.id, latitude: 5.35, longitude: -3.98, radiusKm: 5, active: true }
    });
  } else {
    // Rattrapage : les zones créées avant le Lot 4 ont perdu leur ville
    // (l'ancienne valeur était un texte libre, incompatible avec la clé étrangère).
    await prisma.zone.updateMany({ where: { cityId: null }, data: { cityId: abidjan.id } });
  }

  // Un créneau de disponibilité pour le prestataire Kofi (lundi 09:00-12:00), si pas déjà présent.
  if (kofi) {
    const availCount = await prisma.providerAvailability.count({ where: { providerId: kofi.id } });
    if (availCount === 0) {
      await prisma.providerAvailability.create({
        data: { providerId: kofi.id, weekday: 1, startTime: "09:00", endTime: "12:00" }
      });
    }
  }

  // === Données de démonstration US5 : réglages + modèle de notification ===
  const settingSeeds = [
    { key: "platform.name", value: "PRESTGO", type: "string", description: "Nom affiché de la plateforme" },
    { key: "missions.max_reschedule", value: "3", type: "number", description: "Nombre maximum de reports d'une mission" },
    { key: "reviews.enabled", value: "true", type: "boolean", description: "Autoriser les avis" },
    // === Lot 6 : réglages de la surface mobile (§13) ===
    // Ces valeurs pilotent des règles métier qui doivent pouvoir être ajustées
    // sans redéploiement : un délai de prévenance ou une fenêtre d'avis se
    // règlent en exploitation, pas dans le code.
    {
      key: "provider.required_document_types",
      value: '["id_card"]',
      type: "json",
      description: "Types de justificatifs obligatoires avant soumission d'un dossier prestataire"
    },
    {
      key: "mission.min_lead_time_minutes",
      value: "60",
      type: "number",
      description: "Délai minimum entre la réservation et l'intervention"
    },
    {
      key: "mission.cancellation_notice_hours",
      value: "6",
      type: "number",
      description: "En deçà de ce délai, une annulation est marquée « tardive »"
    },
    {
      key: "mission.start_window_minutes",
      value: "120",
      type: "number",
      description: "Avance maximale avec laquelle un prestataire peut démarrer une mission"
    },
    {
      key: "mission.pending_expiry_hours",
      value: "24",
      type: "number",
      description: "Au-delà, une mission non acceptée expire automatiquement"
    },
    {
      key: "mission.auto_close_days",
      value: "7",
      type: "number",
      description: "Délai après lequel une mission terminée sans litige est clôturée"
    },
    {
      key: "reviews.window_days",
      value: "14",
      type: "number",
      description: "Fenêtre de dépôt d'un avis après la fin de la mission"
    }
  ];
  for (const setting of settingSeeds) {
    await prisma.systemSetting.upsert({
      where: { key: setting.key },
      update: {},
      create: setting
    });
  }

  // Modèles de notification.
  //
  // Ceux du Lot 6 couvrent tout le cycle de vie d'une mission (§12) : sans
  // eux, chaque envoi retomberait sur un texte écrit en dur dans le code, donc
  // impossible à corriger sans redéployer.
  const templateSeeds = [
    { code: "welcome", titleTemplate: "Bienvenue sur PRESTGO", bodyTemplate: "Bonjour {{name}}, votre compte est activé." },
    { code: "mission.created", titleTemplate: "Nouvelle demande de mission", bodyTemplate: "{{clientName}} vous propose une mission le {{scheduledAt}}." },
    { code: "mission.accepted", titleTemplate: "Mission confirmée", bodyTemplate: "{{providerName}} a accepté votre mission du {{scheduledAt}}." },
    { code: "mission.refused", titleTemplate: "Mission refusée", bodyTemplate: "{{providerName}} ne peut pas assurer votre mission. Motif : {{reason}}" },
    { code: "mission.started", titleTemplate: "Intervention démarrée", bodyTemplate: "{{providerName}} a démarré l'intervention." },
    { code: "mission.completed", titleTemplate: "Mission terminée", bodyTemplate: "L'intervention est terminée. Donnez votre avis sur {{providerName}}." },
    { code: "mission.cancelled", titleTemplate: "Mission annulée", bodyTemplate: "La mission du {{scheduledAt}} a été annulée. Motif : {{reason}}" },
    { code: "mission.expired", titleTemplate: "Demande expirée", bodyTemplate: "Faute de réponse, la mission du {{scheduledAt}} a expiré." },
    { code: "mission.reminder", titleTemplate: "Rappel de mission", bodyTemplate: "Rappel : mission prévue demain à {{scheduledAt}}." },
    { code: "mission.reschedule.requested", titleTemplate: "Report demandé", bodyTemplate: "Un report au {{newDate}} vous est proposé. Motif : {{reason}}" },
    { code: "mission.reschedule.accepted", titleTemplate: "Report accepté", bodyTemplate: "La mission est reportée au {{newDate}}." },
    { code: "review.received", titleTemplate: "Nouvel avis", bodyTemplate: "Vous avez reçu un avis de {{rating}}/5." },
    { code: "review.request", titleTemplate: "Votre avis compte", bodyTemplate: "Comment s'est passée votre mission avec {{providerName}} ?" },
    { code: "provider.approved", titleTemplate: "Dossier validé", bodyTemplate: "Votre dossier est validé : vous apparaissez désormais dans la recherche." },
    { code: "provider.changes_requested", titleTemplate: "Dossier à corriger", bodyTemplate: "Votre dossier demande des corrections. Motif : {{reason}}" },
    { code: "provider.rejected", titleTemplate: "Dossier refusé", bodyTemplate: "Votre dossier a été refusé. Motif : {{reason}}" },
    { code: "dispute.opened", titleTemplate: "Litige ouvert", bodyTemplate: "Un litige a été ouvert sur la mission du {{scheduledAt}}." },
    { code: "dispute.message", titleTemplate: "Nouveau message de litige", bodyTemplate: "Un message a été ajouté à votre litige." },
    { code: "dispute.decided", titleTemplate: "Litige tranché", bodyTemplate: "Une décision a été rendue sur votre litige." },
    { code: "chat.message", titleTemplate: "Nouveau message", bodyTemplate: "{{senderName}} : {{preview}}" }
  ];
  for (const template of templateSeeds) {
    await prisma.notificationTemplate.upsert({
      where: { code: template.code },
      update: {},
      create: template
    });
  }
}

await main()
  .finally(async () => {
    await prisma.$disconnect();
  });
