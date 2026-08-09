import "reflect-metadata";
import { ValidationPipe } from "@nestjs/common";
import { NestFactory } from "@nestjs/core";
import { AppModule } from "./app.module.js";
import { HttpExceptionFilter } from "./common/filters/http-exception.filter.js";
import { validationExceptionFactory } from "./common/pipes/validation-exception.factory.js";
import { setupOpenApi } from "./common/openapi/openapi.setup.js";

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule);
  app.setGlobalPrefix("api/v1");
  app.useGlobalPipes(
    new ValidationPipe({
      forbidUnknownValues: true,
      transform: true,
      whitelist: true,
      // Sans cette fabrique, les erreurs de validation sortent sans le nom du
      // champ fautif : le client ne peut pas placer le message sous le bon
      // champ de formulaire. Voir `validation-exception.factory.ts`.
      exceptionFactory: validationExceptionFactory
    })
  );
  // Filtre global : toutes les erreurs sortent au format standard du CDC
  // et aucune information technique ne fuite vers le client.
  app.useGlobalFilters(new HttpExceptionFilter());
  setupOpenApi(app);
  await app.listen(process.env.API_PORT ? Number(process.env.API_PORT) : 3000);
}

void bootstrap();
