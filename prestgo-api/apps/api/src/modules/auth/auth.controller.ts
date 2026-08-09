import { Body, Controller, Headers, HttpCode, Post, UnauthorizedException } from "@nestjs/common";
import { ApiTags, ApiOperation, ApiResponse } from "@nestjs/swagger";
import { Throttle } from "@nestjs/throttler";
import { THROTTLE_LOGIN, THROTTLE_MODERATE, THROTTLE_SENSITIVE } from "../../common/config/throttle.config.js";
import { AuthService } from "./auth.service.js";
import { AccountService } from "./account.service.js";
import {
  ForgotPasswordBodyDto,
  LoginBodyDto,
  LogoutBodyDto,
  RefreshBodyDto,
  RegisterBodyDto,
  ResetPasswordBodyDto,
  SendOtpBodyDto,
  VerifyOtpBodyDto
} from "./dto.js";
import { ok } from "../../common/contracts/api-response.js";
import { Public } from "../../common/decorators/public.decorator.js";

// @Public sur tout le contrôleur : ces routes servent justement à OBTENIR un
// token, on ne peut donc pas exiger d'en avoir déjà un. Toutes les autres
// routes de l'application sont protégées par défaut (voir app.module.ts).
@ApiTags("auth")
@Public()
@Controller("auth")
export class AuthController {
  constructor(
    private readonly authService: AuthService,
    private readonly account: AccountService
  ) {}

  // Maximum 10 tentatives de connexion par minute et par adresse IP.
  // Sans cette limite, un robot peut essayer des milliers de mots de passe.
  @Throttle(THROTTLE_LOGIN)
  @Post("login")
  @HttpCode(200)
  @ApiOperation({ summary: "Login with email and password" })
  @ApiResponse({ status: 200, description: "Returns access and refresh tokens" })
  @ApiResponse({ status: 401, description: "Invalid credentials" })
  @ApiResponse({ status: 429, description: "Too many login attempts" })
  async login(@Body() dto: LoginBodyDto, @Headers("user-agent") userAgent?: string) {
    // Le `User-Agent` est conservé sur la session : c'est ce qui permettra à
    // l'utilisateur de reconnaître ses appareils connectés.
    const tokens = await this.authService.login(dto, userAgent);
    return ok(tokens, undefined, "Authenticated");
  }

  @Throttle(THROTTLE_MODERATE)
  @Post("refresh")
  @HttpCode(200)
  @ApiOperation({ summary: "Refresh access token" })
  @ApiResponse({ status: 200, description: "Returns a new access token and a rotated refresh token" })
  @ApiResponse({ status: 401, description: "Invalid refresh token" })
  async refresh(@Body() dto: RefreshBodyDto, @Headers("user-agent") userAgent?: string) {
    // Le jeton de rafraîchissement TOURNE : celui reçu est révoqué, un nouveau
    // est renvoyé. L'appelant doit donc remplacer celui qu'il stockait.
    const tokens = await this.authService.refresh(dto, userAgent);
    return ok(tokens, undefined, "Refreshed");
  }

  // Inscription. Fortement limitée en débit : sans cela, un robot pourrait
  // créer des milliers de comptes.
  @Throttle(THROTTLE_SENSITIVE)
  @Post("register")
  @HttpCode(201)
  @ApiOperation({ summary: "Create a user account" })
  @ApiResponse({ status: 201, description: "Account created, pending verification" })
  @ApiResponse({ status: 409, description: "Email or phone already used" })
  async register(@Body() dto: RegisterBodyDto) {
    const user = await this.account.register(dto);
    return ok(user, undefined, "Compte créé. Vérifiez votre téléphone ou votre email pour l'activer.");
  }

  // Demande de réinitialisation. La réponse est identique que le compte
  // existe ou non, pour ne pas révéler qui est inscrit.
  @Throttle(THROTTLE_SENSITIVE)
  @Post("forgot-password")
  @HttpCode(200)
  @ApiOperation({ summary: "Request a password reset link" })
  async forgotPassword(@Body() dto: ForgotPasswordBodyDto) {
    const result = await this.account.forgotPassword(dto.email);
    return ok(result, undefined, result.message);
  }

  @Throttle(THROTTLE_MODERATE)
  @Post("reset-password")
  @HttpCode(200)
  @ApiOperation({ summary: "Reset the password using a token" })
  @ApiResponse({ status: 400, description: "Invalid or expired token" })
  async resetPassword(@Body() dto: ResetPasswordBodyDto) {
    return ok(await this.account.resetPassword(dto.token, dto.password), undefined, "Mot de passe mis à jour");
  }

  @Throttle(THROTTLE_SENSITIVE)
  @Post("otp/send")
  @HttpCode(200)
  @ApiOperation({ summary: "Send a one-time code" })
  async sendOtp(@Body() dto: SendOtpBodyDto) {
    const result = await this.account.sendOtp(dto.target, dto.purpose ?? "phone_verification");
    return ok(result, undefined, result.message);
  }

  /**
   * POST /auth/otp/verify — vérifie un code, ou connecte par téléphone.
   *
   * `purpose: "login"` couvre l'écart n°2 du cahier des charges mobile : un
   * compte inscrit avec un numéro de téléphone seul (sans email) n'avait
   * aucun moyen de se connecter, `LoginBodyDto` n'acceptant qu'un email.
   * `login` figurait pourtant déjà parmi les motifs acceptés par
   * `SendOtpBodyDto`/`VerifyOtpBodyDto` — l'intention existait, la route non.
   *
   * Le parcours : `POST /auth/otp/send` avec `purpose: "login"` sur le
   * numéro, puis ce même appel avec le code reçu renvoie un couple de jetons,
   * exactement comme `POST /auth/login`, mais sans mot de passe.
   */
  @Throttle(THROTTLE_MODERATE)
  @Post("otp/verify")
  @HttpCode(200)
  @ApiOperation({ summary: "Verify a one-time code (purpose=login also completes a passwordless login)" })
  @ApiResponse({ status: 200, description: "Code vérifié ; jetons émis si purpose=login" })
  @ApiResponse({ status: 400, description: "Invalid or expired code" })
  @ApiResponse({ status: 401, description: "purpose=login : code valide, mais aucun compte actif ne correspond" })
  async verifyOtp(@Body() dto: VerifyOtpBodyDto, @Headers("user-agent") userAgent?: string) {
    const purpose = dto.purpose ?? "phone_verification";
    const result = await this.account.verifyOtp(dto.target, dto.code, purpose);

    if (purpose === "login") {
      // Le code est déjà prouvé valide (sinon `verifyOtp` aurait levé une
      // exception) : reste à savoir si un compte UTILISABLE lui correspond.
      // Le révéler ici n'ouvre rien : avoir reçu et ressaisi le bon code
      // prouve déjà la maîtrise du téléphone ou de l'email, exactement ce que
      // `/auth/login` demande par mot de passe — contrairement à
      // `forgot-password` ou `otp/send`, où la réponse doit rester identique
      // qu'un compte existe ou non.
      if (!result.userId || result.userStatus !== "active") {
        throw new UnauthorizedException("Account is not active");
      }
      const tokens = await this.authService.issueTokensFor(result.userId, userAgent);
      return ok({ accessToken: tokens.accessToken, refreshToken: tokens.refreshToken }, undefined, "Authenticated");
    }

    // Forme inchangée pour les deux autres motifs : { verified, activated }.
    return ok(
      { verified: result.verified, activated: result.activated },
      undefined,
      result.activated ? "Compte activé" : "Code vérifié"
    );
  }

  @Post("logout")
  @HttpCode(200)
  @ApiOperation({ summary: "Logout current session" })
  @ApiResponse({ status: 200, description: "Successfully logged out" })
  async logout(@Body() dto: LogoutBodyDto, @Headers("authorization") authorization?: string) {
    await this.authService.logout(authorization, dto?.refreshToken);
    return ok({ loggedOut: true }, undefined, "Logged out");
  }
}
