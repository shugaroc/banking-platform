import { HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { switchMap, take } from 'rxjs';
import { AuthService } from '../../features/auth/services/auth.service';

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const authService = inject(AuthService);

  return authService.session$.pipe(
    take(1),
    switchMap(session => {
      if (session?.access_token) {
        const authReq = req.clone({
          headers: req.headers.set('Authorization', `Bearer ${session.access_token}`)
        });
        return next(authReq);
      }
      return next(req);
    })
  );
};
