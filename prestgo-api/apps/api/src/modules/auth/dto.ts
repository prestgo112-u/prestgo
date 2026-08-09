import { IsEmail, IsIn, IsOptional, IsString, Matches, MaxLength, MinLength } from "class-validator";

// Un mot de passe doit contenir au moins une lettre et un chiffre : sans cette
// règle, « aaaaaaaa » passerait la seule vérification de longueur.
const PASSWORD_PATTERN = /^(?=.*[A-Za-z])(?=.*\d).+$/;
const PASSWORD_MESSAGE = "Le mot de passe doit contenir au moins 8 caractères, dont une lettre et un chiffre";

export class RegisterBodyDto {
  @IsOptional()
  @IsEmail({}, { message: "Adresse email invalide" })
  email?: string;

  // Format international ou local ivoirien, chiffres et espaces autorisés.
  @IsOptional()
  @Matches(/^\+?[0-9\s-]{8,20}$/, { message: "Numéro de téléphone invalide" })
  phone?: string;

  @IsString()
  @MinLength(8, { message: PASSWORD_MESSAGE })
  @MaxLength(128)
  @Matches(PASSWORD_PATTERN, { message: PASSWORD_MESSAGE })
  password!: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  firstName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  lastName?: string;
}

export class ForgotPasswordBodyDto {
  @IsEmail({}, { message: "Adresse email invalide" })
  email!: string;
}

export class ResetPasswordBodyDto {
  @IsString()
  @MinLength(10, { message: "Jeton de réinitialisation invalide" })
  token!: string;

  @IsString()
  @MinLength(8, { message: PASSWORD_MESSAGE })
  @MaxLength(128)
  @Matches(PASSWORD_PATTERN, { message: PASSWORD_MESSAGE })
  password!: string;
}

// Motifs d'usage d'un code OTP.
const OTP_PURPOSES = ["phone_verification", "email_verification", "login"];

export class SendOtpBodyDto {
  // Destinataire : numéro de téléphone ou adresse email.
  @IsString()
  @MinLength(4)
  @MaxLength(120)
  target!: string;

  @IsOptional()
  @IsIn(OTP_PURPOSES, { message: `Motif inconnu (${OTP_PURPOSES.join(", ")})` })
  purpose?: string;
}

export class VerifyOtpBodyDto {
  @IsString()
  @MinLength(4)
  @MaxLength(120)
  target!: string;

  @Matches(/^\d{6}$/, { message: "Le code doit contenir 6 chiffres" })
  code!: string;

  @IsOptional()
  @IsIn(OTP_PURPOSES, { message: `Motif inconnu (${OTP_PURPOSES.join(", ")})` })
  purpose?: string;
}

export class LoginBodyDto {
  @IsEmail({}, { message: "Adresse email invalide" })
  email!: string;

  @IsString()
  @MinLength(1, { message: "Le mot de passe est obligatoire" })
  password!: string;
}

export class RefreshBodyDto {
  @IsString()
  @MinLength(1, { message: "Le refresh token est obligatoire" })
  refreshToken!: string;
}

/**
 * Corps de `POST /auth/logout`.
 *
 * Le jeton de rafraîchissement est facultatif : le fournir permet de fermer
 * précisément la session concernée. À défaut, on se rabat sur celle portée par
 * le jeton d'accès. Les deux chemins révoquent réellement la session — c'est
 * la différence avec l'ancienne déconnexion, qui ne faisait que journaliser.
 */
export class LogoutBodyDto {
  @IsOptional()
  @IsString()
  @MaxLength(256)
  refreshToken?: string;
}

/** Corps de `POST /me/password` (§3). */
export class ChangePasswordBodyDto {
  @IsString()
  @MinLength(1, { message: "Le mot de passe actuel est obligatoire" })
  currentPassword!: string;

  @IsString()
  @MinLength(8, { message: PASSWORD_MESSAGE })
  @MaxLength(128)
  @Matches(PASSWORD_PATTERN, { message: PASSWORD_MESSAGE })
  newPassword!: string;
}
