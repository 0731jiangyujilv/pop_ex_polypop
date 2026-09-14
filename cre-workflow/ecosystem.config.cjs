module.exports = {
  apps: [
    {
      name: "pop-resolution-simulate",
      script: "cre",
      args: "workflow simulate pop-resolution --broadcast",
      cwd: "/Users/just/workspace/aibkh/chainlink/arc-uni-polypop/cre-workflow",
      cron_restart: "*/10 * * * *",
      autorestart: false,
      watch: false,
      interpreter: "none",
      out_file: "logs/pop-resolution-out.log",
      error_file: "logs/pop-resolution-error.log",
      time: true,
    },
  ],
};
