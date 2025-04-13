# Banking Platform

A modern banking platform built with Angular and Supabase.

## Prerequisites

- Node.js (v20.x or later)
- npm (v10.x or later)
- Angular CLI (v17.x)

## Setup

1. Install dependencies:
```bash
npm install
```

2. Set up environment variables:
- Copy `src/environments/environment.template.ts` to `src/environments/environment.ts`
- Add your Supabase credentials

## Development

- Run development server: `npm start`
- Run tests: `npm test`
- Run linting: `npm run lint`
- Format code: `npm run format`

## Building

```bash
npm run build
```

## CI/CD

The project uses GitHub Actions for CI/CD pipeline, which includes:
- Linting
- Building
- Testing
- Artifact generation

## Project Structure

```
src/
├── app/
│   ├── core/          # Singleton services, guards
│   ├── features/      # Feature modules
│   └── shared/        # Shared components, pipes, directives
├── assets/            # Static assets
└── environments/      # Environment configurations
```

## Contributing

1. Create a feature branch from `main`
2. Make your changes
3. Run tests and ensure linting passes
4. Submit a pull request

## License

[MIT License](LICENSE)
