import { IsEmail, IsOptional, IsString, Matches, MaxLength, MinLength } from 'class-validator';

export class RegisterDto {
  @IsString()
  @Matches(/^[a-z0-9_.]{3,32}$/i, {
    message: 'username: 3-32 chars, letters/numbers/underscore/dot only',
  })
  username: string;

  @IsString()
  @MinLength(1)
  @MaxLength(128)
  fullName: string;

  @IsEmail()
  email: string;

  @IsString()
  @MinLength(8)
  @MaxLength(72)
  password: string;
}

export class LoginDto {
  @IsString()
  login: string; // username or email

  @IsString()
  password: string;

  @IsOptional()
  @IsString()
  fcmToken?: string;
}