# ─── Stage 1: Build ──────────────────────────────────────────────────────────
FROM dart:stable AS build

WORKDIR /app

# Bağımlılıkları önce al (layer cache için)
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get

# Kaynak kodu kopyala ve derle
COPY . .
RUN dart compile exe bin/server.dart -o /app/inventra_server

# ─── Stage 2: Runtime ─────────────────────────────────────────────────────────
FROM debian:stable-slim

# SQLite çalışma zamanı + sertifikalar
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      libsqlite3-0 \
      ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Derlenmiş binary'yi kopyala
COPY --from=build /app/inventra_server .

# Veri dizini — container yeniden başlasa bile veriler korunur
VOLUME /app/data

# Sunucu portu (docker-compose veya -p ile dışa açılır)
EXPOSE 5000

# ─── Ortam Değişkenleri (İlk Kurulum İçin) ────────────────────────────────────
# Bu değişkenler ayarlandığında sunucu ilk başlangıçta otomatik kurulum yapar.
# Kurulum tamamlandıktan sonra ENV satırlarını docker-compose.yml'den kaldırabilirsiniz.
#
# ENV INVENTRA_BUSINESS_NAME="Mağazam"
# ENV INVENTRA_ADMIN_ID="1000"
# ENV INVENTRA_ADMIN_PASSWORD="güvenli_şifre"
# ENV INVENTRA_PORT="5000"
# ENV INVENTRA_HOST="0.0.0.0"

CMD ["./inventra_server"]
