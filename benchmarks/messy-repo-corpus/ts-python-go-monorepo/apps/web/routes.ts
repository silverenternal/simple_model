import client from "../generated/client";

export function registerRoutes(app: any) {
  if (process.env.FEATURE_NEW_ROUTE) {
    app.get("/v1/users", client.users);
  }
}
