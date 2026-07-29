import { Injectable, InternalServerErrorException } from "@nestjs/common";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve, sep } from "node:path";

/**
 * Écrit et relit le contenu binaire des fichiers sur le disque.
 *
 * On sépare volontairement deux choses :
 *   - la table `File` en base = les MÉTADONNÉES (nom, type, taille, visibilité) ;
 *   - ce service = le CONTENU réel, rangé sous un dossier racine.
 *
 * Le dossier racine se configure avec la variable d'environnement
 * `FILE_STORAGE_DIR` (par défaut : `storage/` à la racine de l'API).
 * Plus tard, on pourra remplacer ce service par un stockage S3 sans toucher
 * au reste du code.
 */
@Injectable()
export class FileStorageService {
  private readonly root = resolve(process.env.FILE_STORAGE_DIR ?? "storage");

  async save(storageKey: string, content: Buffer): Promise<void> {
    const target = this.resolvePath(storageKey);
    await mkdir(dirname(target), { recursive: true });
    await writeFile(target, content);
  }

  async read(storageKey: string): Promise<Buffer> {
    return readFile(this.resolvePath(storageKey));
  }

  /**
   * Transforme une clé de stockage en chemin réel, en refusant tout chemin qui
   * sortirait du dossier racine (protection contre les « ../../ »).
   * Les clés sont générées par le serveur, mais cette vérification reste une
   * seconde barrière si une clé venait un jour d'ailleurs.
   */
  private resolvePath(storageKey: string): string {
    const target = resolve(join(this.root, storageKey));
    if (target !== this.root && !target.startsWith(this.root + sep)) {
      throw new InternalServerErrorException("Clé de stockage invalide");
    }
    return target;
  }
}
