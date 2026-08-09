import { Type } from "class-transformer";
import { IsInt, IsOptional, Max, Min } from "class-validator";

export class DashboardChartsQueryDto {
  // Profondeur d'historique de la courbe des inscriptions, en jours.
  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: "days doit être un nombre entier" })
  @Min(7, { message: "days doit valoir au moins 7" })
  @Max(365, { message: "days ne peut pas dépasser 365" })
  days?: number;
}
