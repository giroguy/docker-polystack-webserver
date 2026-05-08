// Add an entry here each time a new service repo is deployed to the server.
// Then run: docker exec node pm2 reload ecosystem.config.js --update-env
// Commit and push so the repo stays in sync.
//
// Template (Node):
// {
//   name: 'service-name',
//   cwd: '/app/endpoint-name',
//   script: 'index.js',          // check package.json "main" for correct entry point
//   env: { PORT: XXXX, NODE_ENV: 'production' }
// }
//
// Template (Go binary):
// {
//   name: 'endpoint-name',
//   cwd: '/go/endpoint-name',
//   script: './binary-name',     // pre-built binary deployed by GitHub Actions
//   interpreter: 'none',
//   env: { PORT: XXXX }
// }

module.exports = {
  apps: [

    // Keeps PM2 running when no services are deployed yet.
    // Safe to leave permanently — uses no resources.
    {
      name: 'placeholder',
      script: 'node',
      args: '-e "setInterval(() => {}, 1000 * 60 * 60)"',
    },

    // Add your services here:
    // {
    //   name: 'my-api',
    //   cwd: '/app/my-api',
    //   script: 'index.js',
    //   env: { PORT: 3001, NODE_ENV: 'production' }
    // },

  ]
}
