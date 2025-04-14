import { Routes } from '@angular/router';
import { AuthGuard } from '@core/guards/auth-guard.guard';
import { DashboardComponent } from './features/dashboard/dashboard.component';

export const routes: Routes = [ 
    {
        path: '',
        component: DashboardComponent,
        canActivate: [AuthGuard],
    },
  {
    path: 'auth',
    loadChildren: () => import('./features/auth/auth.routes').then(m => m.AUTH_ROUTES)
  },
  {
    path: '',
    redirectTo: '/auth/login',
    pathMatch: 'full'
  },
  // {
  //   path: '**',
  //   redirectTo: '/auth/login'
  // }
];
