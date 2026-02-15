const http = require("node:http")
const fs = require("node:fs")
const path = require("node:path")

const PORT = parseInt(process.env.PORT || "18089", 10)
const SERVE_DIR = path.join(__dirname, "serve")

const server = http.createServer((req, res) => {
  const decoded = decodeURIComponent(req.url.split("?")[0].replace(/^\/+/, ""))
  const filePath = path.resolve(SERVE_DIR, decoded)

  // Path traversal protection
  if (!filePath.startsWith(SERVE_DIR + path.sep) && filePath !== SERVE_DIR) {
    console.log(`BLOCKED ${req.method} ${req.url} (path traversal)`)
    res.writeHead(403)
    res.end("Forbidden")
    return
  }

  console.log(`${req.method} ${req.url} -> ${decoded}`)

  fs.readFile(filePath, (err, data) => {
    if (err) {
      console.log(`  404 Not Found`)
      res.writeHead(404)
      res.end("Not found")
      return
    }

    console.log(`  200 OK (${data.length} bytes)`)
    res.writeHead(200)
    res.end(data)

    if (decoded.endsWith(".mpackage")) {
      console.log("\nUpdate complete — shutting down.")
      server.close()
    }
  })
})

server.listen(PORT, () => {
  console.log(`Serving files from: ${SERVE_DIR}`)
  console.log(`Listening on: http://localhost:${PORT}`)
  console.log()
  console.log("Press Ctrl+C to stop")
})
