import { Routes } from '@angular/router';
import { AuthGuard } from '@core/guards/auth-guard.guard';
import { NgZone, inject } from '@angular/core';

export const AUTH_ROUTES: Routes = [
  {
    path: '',
    children: [
      {
        path: 'login',
        loadComponent: () => import('./login/login.component').then(m => m.LoginComponent),
        resolve: {
          init: () => {
            const ngZone = inject(NgZone);
            return ngZone.run(() => Promise.resolve(true));
          }
        }
      },
      {
        path: 'signup',
        loadComponent: () => import('./signup/signup.component').then(m => m.SignupComponent),
        resolve: {
          init: () => {
            const ngZone = inject(NgZone);
            return ngZone.run(() => Promise.resolve(true));
          }
        }
      },
      {
        path: 'forgot-password',
        loadComponent: () => import('./forgot-password/forgot-password.component').then(m => m.ForgotPasswordComponent),
        resolve: {
          init: () => {
            const ngZone = inject(NgZone);
            return ngZone.run(() => Promise.resolve(true));
          }
        }
      },
      {
        path: 'reset-password',
        loadComponent: () => import('./reset-password/reset-password.component').then(m => m.ResetPasswordComponent),
        resolve: {
          init: () => {
            const ngZone = inject(NgZone);
            return ngZone.run(() => Promise.resolve(true));
          }
        }
      },
      {
        path: 'verify-email',
        loadComponent: () => import('./verify-email/verify-email.component').then(m => m.VerifyEmailComponent),
        resolve: {
          init: () => {
            const ngZone = inject(NgZone);
            return ngZone.run(() => Promise.resolve(true));
          }
        }
      },
      {
        path: 'confirm-signup',
        loadComponent: () => import('./confirm-signup/confirm-signup.component').then(m => m.ConfirmSignupComponent),
        resolve: {
          init: () => {
            const ngZone = inject(NgZone);
            return ngZone.run(() => Promise.resolve(true));
          }
        }
      },
      {
        path: '',
        redirectTo: 'login',
        pathMatch: 'full'
      }
    ]
  }
];
