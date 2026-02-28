# Elasticsearch + nori 한국어 형태소 분석 플러그인
# 베이스 이미지에 nori 플러그인을 사전 설치한다.
ARG ES_VERSION=8.12.0
FROM docker.elastic.co/elasticsearch/elasticsearch:${ES_VERSION}

# nori 한국어 형태소 분석 플러그인 설치
RUN bin/elasticsearch-plugin install analysis-nori

# 스냅샷 저장소 디렉토리 생성 (ES 8.x는 기본 uid 1000으로 실행)
USER root
RUN mkdir -p /usr/share/elasticsearch/snapshots && \
    chown -R 1000:0 /usr/share/elasticsearch/snapshots
USER 1000
