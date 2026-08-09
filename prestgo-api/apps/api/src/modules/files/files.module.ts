import { Module } from "@nestjs/common";
import { FilesController } from "./files.controller.js";
import { FileStorageService } from "./file-storage.service.js";
import { PrismaModule } from "../../common/prisma/prisma.module.js";
import { AuthModule } from "../auth/auth.module.js";

@Module({
  // `AuthModule` pour `AuthService` : `GET /files/:id/content` est publique et
  // doit donc résoudre elle-même le porteur du jeton quand il y en a un
  // (voir `FilesController.resolveOptionalActor`).
  imports: [PrismaModule, AuthModule],
  controllers: [FilesController],
  providers: [FileStorageService],
  // Exporté pour que le module des exports puisse écrire ses fichiers CSV.
  exports: [FileStorageService]
})
export class FilesModule {}
