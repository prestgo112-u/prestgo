import { Module } from "@nestjs/common";
import { FilesController } from "./files.controller.js";
import { FileStorageService } from "./file-storage.service.js";
import { PrismaModule } from "../../common/prisma/prisma.module.js";

@Module({
  imports: [PrismaModule],
  controllers: [FilesController],
  providers: [FileStorageService],
  // Exporté pour que le module des exports puisse écrire ses fichiers CSV.
  exports: [FileStorageService]
})
export class FilesModule {}
