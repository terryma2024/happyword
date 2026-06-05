package cool.happyword.wordmagic

import java.io.Closeable
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.util.concurrent.atomic.AtomicBoolean

internal class TestBackendServer private constructor(
    private val serverSocket: ServerSocket,
    private val running: AtomicBoolean,
    private val thread: Thread,
) : Closeable {
    val baseUrl: String = "http://127.0.0.1:${serverSocket.localPort}"

    override fun close() {
        running.set(false)
        runCatching { serverSocket.close() }
        runCatching { thread.join(1_000) }
    }

    companion object {
        fun start(): TestBackendServer {
            val running = AtomicBoolean(true)
            val socket = ServerSocket(0, 50, InetAddress.getByName("127.0.0.1"))
            val thread = Thread {
                while (running.get()) {
                    val client = runCatching { socket.accept() }.getOrNull() ?: continue
                    runCatching { client.use(::handleClient) }
                }
            }.apply {
                name = "wordmagic-test-backend"
                isDaemon = true
                start()
            }
            return TestBackendServer(socket, running, thread)
        }

        private fun handleClient(client: Socket) {
            client.soTimeout = 2_000
            val input = client.getInputStream().bufferedReader(StandardCharsets.UTF_8)
            val requestLine = input.readLine().orEmpty()
            if (requestLine.isBlank()) return
            var contentLength = 0
            while (true) {
                val line = input.readLine() ?: break
                if (line.isBlank()) break
                val separator = line.indexOf(':')
                if (separator > 0 && line.substring(0, separator).equals("Content-Length", ignoreCase = true)) {
                    contentLength = line.substring(separator + 1).trim().toIntOrNull() ?: 0
                }
            }
            val body = if (contentLength > 0) {
                CharArray(contentLength).also { input.read(it) }.concatToString()
            } else {
                ""
            }
            val parts = requestLine.split(' ')
            val method = parts.getOrNull(0).orEmpty()
            val path = URLDecoder.decode(parts.getOrNull(1).orEmpty().substringBefore('?'), "UTF-8")
            val response = when {
                method == "GET" && path == "/api/v1/public/global-packs/latest.json" ->
                    HttpResponse(200, globalPacksJson)
                method == "GET" && path.endsWith("/family-packs/latest.json") ->
                    HttpResponse(200, familyPacksJson)
                method == "POST" && path == "/api/v1/public/pair/redeem" ->
                    redeemPair(body)
                else ->
                    HttpResponse(404, """{"code":"NOT_FOUND"}""")
            }
            writeResponse(client, response)
        }

        private fun redeemPair(body: String): HttpResponse {
            if (body.contains("000001")) {
                return HttpResponse(400, """{"code":"TOKEN_INVALID"}""")
            }
            return HttpResponse(
                200,
                """{"device_token":"device.jwt.token","binding_id":"bind-test-123456","nickname":"小明测试46373","avatar_emoji":"🦁","family_id":"fam-parity","child_profile_id":"child-test-0001","paired_at_ms":"1715526545000","device_id_source":"preferences_fallback"}""",
            )
        }

        private fun writeResponse(client: Socket, response: HttpResponse) {
            val payload = response.body.toByteArray(StandardCharsets.UTF_8)
            val header = buildString {
                append("HTTP/1.1 ${response.status} OK\r\n")
                append("Content-Type: application/json; charset=utf-8\r\n")
                append("Content-Length: ${payload.size}\r\n")
                append("Connection: close\r\n\r\n")
            }.toByteArray(StandardCharsets.UTF_8)
            client.getOutputStream().apply {
                write(header)
                write(payload)
                flush()
            }
        }

        private data class HttpResponse(val status: Int, val body: String)

        private val globalPacksJson = """
            {
              "merged_at": "2026-01-01T00:00:00Z",
              "packs": [{
                "pack_id": "global-colors",
                "name": "Color Harbor",
                "version": 1,
                "published_at": "2026-01-01T00:00:00Z",
                "scene": {
                  "bg_primary": "#FFFFFF",
                  "bg_accent": "#FFFFFF",
                  "boss_name": "",
                  "monsterPlan": [],
                  "bossCandidates": [],
                  "spellbook_cover_url": "https://blob.example/covers/global-colors.png"
                },
                "words": [
                  {"id":"color-red","word":"red","meaning_zh":"红色"},
                  {"id":"color-blue","word":"blue","meaning_zh":"蓝色"},
                  {"id":"color-green","word":"green","meaning_zh":"绿色"}
                ]
              }]
            }
        """.trimIndent()

        private val familyPacksJson = """
            {
              "merged_at": "2026-01-01T00:00:00Z",
              "packs": [{
                "pack_id": "family-space",
                "name": "Family Space",
                "version": 1,
                "published_at": "2026-01-01T00:00:00Z",
                "scene": {
                  "bg_primary": "#FFFFFF",
                  "bg_accent": "#FFFFFF",
                  "boss_name": "",
                  "monsterPlan": [],
                  "bossCandidates": [],
                  "spellbook_cover_url": "https://blob.example/covers/family-space.png"
                },
                "words": [
                  {"id":"space-moon","word":"moon","meaning_zh":"月亮"},
                  {"id":"space-star","word":"star","meaning_zh":"星星"},
                  {"id":"space-sun","word":"sun","meaning_zh":"太阳"}
                ]
              }]
            }
        """.trimIndent()
    }
}
