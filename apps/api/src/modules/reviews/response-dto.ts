import { ApiProperty } from "@nestjs/swagger";

/** DTO de réponse du module avis (§11), reflétant `review-submission.service.ts`. */

export class MyReviewMissionProviderRefDto {
  @ApiProperty() id!: string;
  @ApiProperty() publicName!: string;
  @ApiProperty({ nullable: true }) avatarFileId!: string | null;
}

export class MyReviewMissionRefDto {
  @ApiProperty() id!: string;
  @ApiProperty({ nullable: true }) scheduledAt!: Date | null;
  @ApiProperty({ type: MyReviewMissionProviderRefDto, nullable: true }) provider!: MyReviewMissionProviderRefDto | null;
}

/** Un élément de `GET /me/reviews`. */
export class MyReviewListItemDto {
  @ApiProperty() id!: string;
  @ApiProperty() rating!: number;
  @ApiProperty({ nullable: true }) comment!: string | null;
  @ApiProperty({ enum: ["published", "reported", "hidden", "rejected"] }) status!: string;
  @ApiProperty() createdAt!: Date;
  @ApiProperty({ type: MyReviewMissionRefDto }) mission!: MyReviewMissionRefDto;
}

/** Réponse de `POST /reviews/:id/report`. */
export class ReportReviewResultDto {
  @ApiProperty() reported!: boolean;
}
