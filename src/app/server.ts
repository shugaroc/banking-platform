import { bootstrapApplication } from '@angular/platform-browser';
import { AppComponent } from './app.component';
import { appConfig } from './app.config';
import { provideClientHydration } from '@angular/platform-browser';
import { provideServerRendering } from '@angular/platform-server';

const serverConfig = {
  ...appConfig,
  providers: [
    ...appConfig.providers,
    provideServerRendering(),
    provideClientHydration()
  ]
};

bootstrapApplication(AppComponent, serverConfig)
  .catch(err => console.error('Error bootstrapping server app:', err));
