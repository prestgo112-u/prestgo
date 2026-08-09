import { Type } from "class-transformer";
import {
  IsIn,
  IsInt,
  IsLatitude,
  IsLongitude,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  Max,
  MaxLength,
  Min
} from "class-validator";
import { PaginationQueryDto } from "../../common/dto/pagination.dto.js";
import { EmptyToUndefined } from "../../common/dto/transforms.js";
import { DEFAULT_SEARCH_RADIUS_KM, MAX_SEARCH_RADIUS_KM } from "./provider-search.service.js";

/**
 * Paramètres de `GET /providers/search` (§7).
 *
 * Tout est facultatif : sans aucun filtre, la recherche renvoie les
 * prestataires validés et réservables, triés par note. C'est exactement ce
 * qu'affiche l'écran d'accueil avant que le client n'autorise la géolocalisation.
 */
export class ProviderSearchQueryDto extends PaginationQueryDto {
  @IsOptional()
  @EmptyToUndefined()
  @IsUUID(undefined, { message: "Catégorie invalide" })
  categoryId?: string;

  @IsOptional()
  @EmptyToUndefined()
  @IsUUID(undefined, { message: "Type de service invalide" })
  serviceTypeId?: string;

  @IsOptional()
  @Type(() => Number)
  @IsLatitude({ message: "Latitude invalide" })
  latitude?: number;

  @IsOptional()
  @Type(() => Number)
  @IsLongitude({ message: "Longitude invalide" })
  longitude?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber({}, { message: "Le rayon doit être un nombre de kilomètres" })
  @Min(1, { message: "Le rayon doit valoir au moins 1 km" })
  @Max(MAX_SEARCH_RADIUS_KM, { message: `Le rayon ne peut pas dépasser ${MAX_SEARCH_RADIUS_KM} km` })
  radiusKm?: number = DEFAULT_SEARCH_RADIUS_KM;

  @IsOptional()
  @EmptyToUndefined()
  @IsUUID(undefined, { message: "Zone invalide" })
  zoneId?: string;

  // Date d'intervention souhaitée, au format AAAA-MM-JJ.
  @IsOptional()
  @EmptyToUndefined()
  @Matches(/^\d{4}-\d{2}-\d{2}$/, { message: "« date » doit être au format AAAA-MM-JJ" })
  date?: string;

  @IsOptional()
  @EmptyToUndefined()
  @Matches(/^([01]\d|2[0-3]):[0-5]\d$/, { message: "« startTime » doit être au format HH:MM" })
  startTime?: string;

  @IsOptional()
  @Type(() => Number)
  @IsNumber({}, { message: "La note minimale doit être un nombre" })
  @Min(0)
  @Max(5, { message: "La note minimale ne peut pas dépasser 5" })
  minRating?: number;

  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(120)
  q?: string;

  /**
   * Redéfinit `sort` de `PaginationQueryDto` avec les seules valeurs qui ont un
   * sens ici. Une valeur libre serait acceptée puis ignorée — exactement le
   * piège que le §15.4 demande de refermer.
   */
  @IsOptional()
  @EmptyToUndefined()
  @IsIn(["distance", "rating", "recent"], { message: "Tri accepté : distance, rating, recent" })
  declare sort?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(50, { message: "limit ne peut pas dépasser 50 sur la recherche" })
  declare limit?: number;
}
