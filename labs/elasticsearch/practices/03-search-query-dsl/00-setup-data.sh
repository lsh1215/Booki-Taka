#!/bin/bash
# ==============================================================
# 00-setup-data.sh
# 검색 실습용 전자상거래 상품 샘플 데이터 로딩
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}
INDEX="products"

echo "============================================================"
echo "  00. 샘플 데이터 로딩"
echo "  인덱스: $INDEX | ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

# --------------------------------------------------------------
# STEP 1: 인덱스 삭제 및 재생성
# --------------------------------------------------------------
echo ">>> [STEP 1] 기존 인덱스 삭제"
curl -s -X DELETE "$ES_HOST/$INDEX" | jq .
echo ""

echo ">>> [STEP 2] 인덱스 생성 및 매핑 설정"
curl -s -X PUT "$ES_HOST/$INDEX" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "refresh_interval": "1s"
    },
    "mappings": {
      "properties": {
        "title":       {"type": "text", "fields": {"keyword": {"type": "keyword"}}},
        "category":    {"type": "keyword"},
        "price":       {"type": "integer"},
        "brand":       {"type": "keyword"},
        "description": {"type": "text"},
        "created_at":  {"type": "date", "format": "yyyy-MM-dd"},
        "in_stock":    {"type": "boolean"},
        "rating":      {"type": "float"},
        "tags":        {"type": "keyword"}
      }
    }
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 2: 데이터 색인 (Bulk API - 배치 1)
# --------------------------------------------------------------
echo ">>> [STEP 3] 샘플 데이터 색인 (배치 1/4)"
curl -s -X POST "$ES_HOST/$INDEX/_bulk" \
  -H 'Content-Type: application/json' \
  -d '{"index": {"_id": "1"}}
{"title": "삼성 갤럭시 S24 울트라 256GB", "category": "스마트폰", "price": 1599000, "brand": "Samsung", "description": "최신 AI 기능과 S-Pen을 탑재한 플래그십 스마트폰. 200MP 카메라로 전문적인 사진 촬영 가능", "created_at": "2024-01-17", "in_stock": true, "rating": 4.8, "tags": ["스마트폰", "삼성", "안드로이드", "플래그십", "AI"]}
{"index": {"_id": "2"}}
{"title": "Apple 아이폰 15 Pro 128GB", "category": "스마트폰", "price": 1550000, "brand": "Apple", "description": "티타늄 소재와 A17 Pro 칩을 탑재한 최고급 스마트폰. 프로급 카메라 시스템 탑재", "created_at": "2023-09-22", "in_stock": true, "rating": 4.7, "tags": ["스마트폰", "애플", "iOS", "플래그십"]}
{"index": {"_id": "3"}}
{"title": "LG 그램 17 노트북 코어 i7", "category": "노트북", "price": 1890000, "brand": "LG", "description": "17인치 대화면과 가벼운 무게를 동시에 실현. 장시간 배터리 사용 가능한 업무용 노트북", "created_at": "2024-02-05", "in_stock": true, "rating": 4.5, "tags": ["노트북", "LG", "업무용", "경량"]}
{"index": {"_id": "4"}}
{"title": "삼성 갤럭시 버즈2 Pro 무선 이어폰", "category": "이어폰", "price": 259000, "brand": "Samsung", "description": "ANC 액티브 노이즈 캔슬링 기능과 고음질 사운드. 삼성 기기와 완벽한 연동", "created_at": "2023-08-10", "in_stock": true, "rating": 4.3, "tags": ["이어폰", "삼성", "무선", "ANC", "블루투스"]}
{"index": {"_id": "5"}}
{"title": "Apple 에어팟 프로 2세대", "category": "이어폰", "price": 359000, "brand": "Apple", "description": "애플의 최신 ANC 이어폰. H2 칩 기반의 강력한 노이즈 캔슬링과 투명 모드 지원", "created_at": "2022-09-23", "in_stock": true, "rating": 4.6, "tags": ["이어폰", "애플", "무선", "ANC"]}
{"index": {"_id": "6"}}
{"title": "소니 WH-1000XM5 헤드폰", "category": "헤드폰", "price": 449000, "brand": "Sony", "description": "업계 최고 수준의 노이즈 캔슬링. 30시간 배터리 및 멀티포인트 연결 지원", "created_at": "2022-05-12", "in_stock": false, "rating": 4.9, "tags": ["헤드폰", "소니", "ANC", "프리미엄"]}
{"index": {"_id": "7"}}
{"title": "삼성 65인치 QLED 4K TV", "category": "TV", "price": 1290000, "brand": "Samsung", "description": "양자점 기술로 구현한 생생한 색감. 게임 최적화 모드와 스마트 TV 기능 탑재", "created_at": "2024-01-20", "in_stock": true, "rating": 4.6, "tags": ["TV", "삼성", "QLED", "4K", "스마트TV"]}
{"index": {"_id": "8"}}
{"title": "LG OLED evo 65인치 TV", "category": "TV", "price": 2490000, "brand": "LG", "description": "OLED 패널의 완벽한 블랙과 무한 명암비. 게이머와 영화 애호가를 위한 최고의 TV", "created_at": "2024-03-01", "in_stock": true, "rating": 4.8, "tags": ["TV", "LG", "OLED", "4K", "프리미엄"]}
{"index": {"_id": "9"}}
{"title": "로지텍 MX Master 3S 무선 마우스", "category": "마우스", "price": 129000, "brand": "Logitech", "description": "업무 생산성을 위한 최고급 무선 마우스. 다중 기기 연결과 맞춤형 버튼 설정 지원", "created_at": "2022-06-05", "in_stock": true, "rating": 4.7, "tags": ["마우스", "로지텍", "무선", "업무용"]}
{"index": {"_id": "10"}}
{"title": "Apple 매직 키보드 한국어", "category": "키보드", "price": 139000, "brand": "Apple", "description": "맥OS와 완벽히 연동되는 애플 공식 키보드. 얇은 디자인과 조용한 타건감", "created_at": "2023-11-07", "in_stock": true, "rating": 4.2, "tags": ["키보드", "애플", "무선", "맥OS"]}
' | jq .errors

echo ">>> [STEP 3] 샘플 데이터 색인 (배치 2/4)"
curl -s -X POST "$ES_HOST/$INDEX/_bulk" \
  -H 'Content-Type: application/json' \
  -d '{"index": {"_id": "11"}}
{"title": "삼성 32인치 QHD 게이밍 모니터", "category": "모니터", "price": 589000, "brand": "Samsung", "description": "165Hz 주사율과 1ms 응답시간. FreeSync Premium Pro 지원으로 부드러운 게임 화면", "created_at": "2023-12-15", "in_stock": true, "rating": 4.5, "tags": ["모니터", "삼성", "게이밍", "QHD"]}
{"index": {"_id": "12"}}
{"title": "LG 울트라와이드 34인치 모니터", "category": "모니터", "price": 699000, "brand": "LG", "description": "21:9 비율의 넓은 화면으로 멀티태스킹에 최적화. 업무와 창작 작업에 이상적", "created_at": "2023-09-18", "in_stock": true, "rating": 4.4, "tags": ["모니터", "LG", "울트라와이드", "업무용"]}
{"index": {"_id": "13"}}
{"title": "닌텐도 스위치 OLED 모델", "category": "게임기", "price": 399000, "brand": "Nintendo", "description": "7인치 OLED 화면과 개선된 스피커. 집에서도 이동 중에도 즐기는 하이브리드 게임기", "created_at": "2021-10-08", "in_stock": true, "rating": 4.7, "tags": ["게임기", "닌텐도", "OLED", "휴대용"]}
{"index": {"_id": "14"}}
{"title": "소니 플레이스테이션 5 디스크에디션", "category": "게임기", "price": 729000, "brand": "Sony", "description": "차세대 게임 경험. SSD로 구현한 빠른 로딩과 듀얼센스 햅틱 피드백 컨트롤러", "created_at": "2020-11-12", "in_stock": false, "rating": 4.8, "tags": ["게임기", "소니", "PS5", "콘솔"]}
{"index": {"_id": "15"}}
{"title": "Microsoft Xbox Series X", "category": "게임기", "price": 629000, "brand": "Microsoft", "description": "12 테라플롭 연산력의 강력한 게임기. Xbox Game Pass로 수백 개의 게임 즐기기", "created_at": "2020-11-10", "in_stock": true, "rating": 4.6, "tags": ["게임기", "마이크로소프트", "Xbox", "콘솔"]}
{"index": {"_id": "16"}}
{"title": "아이패드 프로 12.9인치 M2", "category": "태블릿", "price": 1499000, "brand": "Apple", "description": "M2 칩 탑재로 노트북 수준의 성능. 리퀴드 레티나 XDR 디스플레이와 Apple Pencil 지원", "created_at": "2022-10-18", "in_stock": true, "rating": 4.8, "tags": ["태블릿", "애플", "iPad", "M2"]}
{"index": {"_id": "17"}}
{"title": "삼성 갤럭시 탭 S9 울트라", "category": "태블릿", "price": 1399000, "brand": "Samsung", "description": "14.6인치 AMOLED 화면과 S-Pen 기본 제공. 멀티태스킹과 창작 작업에 최적화된 안드로이드 태블릿", "created_at": "2023-07-26", "in_stock": true, "rating": 4.6, "tags": ["태블릿", "삼성", "안드로이드", "AMOLED"]}
{"index": {"_id": "18"}}
{"title": "캐논 EOS R50 미러리스 카메라", "category": "카메라", "price": 879000, "brand": "Canon", "description": "입문자를 위한 APS-C 미러리스 카메라. 연속 자동초점과 동영상 촬영에 최적화", "created_at": "2023-02-09", "in_stock": true, "rating": 4.4, "tags": ["카메라", "캐논", "미러리스", "입문용"]}
{"index": {"_id": "19"}}
{"title": "소니 A7 IV 풀프레임 미러리스", "category": "카메라", "price": 2890000, "brand": "Sony", "description": "3300만 화소 풀프레임 센서. 프로급 동영상 기능과 우수한 저조도 성능", "created_at": "2021-12-17", "in_stock": true, "rating": 4.9, "tags": ["카메라", "소니", "미러리스", "풀프레임", "프로"]}
{"index": {"_id": "20"}}
{"title": "다이슨 V15 디텍트 무선청소기", "category": "청소기", "price": 1090000, "brand": "Dyson", "description": "레이저로 먼지를 감지하는 혁신적인 무선청소기. 피에조 센서로 먼지 크기까지 감지", "created_at": "2021-03-25", "in_stock": true, "rating": 4.7, "tags": ["청소기", "다이슨", "무선", "프리미엄"]}
' | jq .errors

echo ">>> [STEP 3] 샘플 데이터 색인 (배치 3/4)"
curl -s -X POST "$ES_HOST/$INDEX/_bulk" \
  -H 'Content-Type: application/json' \
  -d '{"index": {"_id": "21"}}
{"title": "삼성 비스포크 냉장고 4도어", "category": "냉장고", "price": 2190000, "brand": "Samsung", "description": "맞춤 색상 패널로 개성을 표현하는 프리미엄 냉장고. AI 절전 기능 탑재", "created_at": "2023-05-20", "in_stock": true, "rating": 4.5, "tags": ["냉장고", "삼성", "비스포크", "4도어"]}
{"index": {"_id": "22"}}
{"title": "LG 디오스 오브제컬렉션 냉장고", "category": "냉장고", "price": 2450000, "brand": "LG", "description": "오브제 디자인의 프리미엄 냉장고. 인스타뷰 기능으로 내부 확인 가능", "created_at": "2023-07-10", "in_stock": true, "rating": 4.6, "tags": ["냉장고", "LG", "오브제", "인스타뷰"]}
{"index": {"_id": "23"}}
{"title": "애플 맥북 프로 14인치 M3 Pro", "category": "노트북", "price": 2990000, "brand": "Apple", "description": "M3 Pro 칩의 강력한 성능. 크리에이터와 개발자를 위한 최고급 노트북", "created_at": "2023-11-07", "in_stock": true, "rating": 4.9, "tags": ["노트북", "애플", "맥북", "M3", "크리에이터"]}
{"index": {"_id": "24"}}
{"title": "ASUS ROG Zephyrus G14 게이밍 노트북", "category": "노트북", "price": 1990000, "brand": "ASUS", "description": "AMD 라이젠 9와 RTX 4060 탑재 게이밍 노트북. 2560x1600 165Hz 디스플레이", "created_at": "2024-01-10", "in_stock": true, "rating": 4.5, "tags": ["노트북", "ASUS", "게이밍", "AMD"]}
{"index": {"_id": "25"}}
{"title": "레노버 씽크패드 X1 Carbon Gen 11", "category": "노트북", "price": 2490000, "brand": "Lenovo", "description": "비즈니스 최강 노트북. 군사 규격 내구성과 1kg대 초경량 설계", "created_at": "2023-04-20", "in_stock": true, "rating": 4.6, "tags": ["노트북", "레노버", "씽크패드", "비즈니스", "경량"]}
{"index": {"_id": "26"}}
{"title": "샤오미 Redmi Note 13 Pro", "category": "스마트폰", "price": 399000, "brand": "Xiaomi", "description": "200MP 카메라와 AMOLED 화면을 갖춘 가성비 스마트폰", "created_at": "2024-01-15", "in_stock": true, "rating": 4.2, "tags": ["스마트폰", "샤오미", "가성비", "안드로이드"]}
{"index": {"_id": "27"}}
{"title": "구글 픽셀 8 Pro", "category": "스마트폰", "price": 1290000, "brand": "Google", "description": "Google AI 기능이 집약된 순수 안드로이드 스마트폰. 최고의 야간 촬영 성능", "created_at": "2023-10-12", "in_stock": true, "rating": 4.5, "tags": ["스마트폰", "구글", "픽셀", "안드로이드", "AI"]}
{"index": {"_id": "28"}}
{"title": "JBL Charge 5 블루투스 스피커", "category": "스피커", "price": 219000, "brand": "JBL", "description": "IP67 방수 방진 블루투스 스피커. 20시간 배터리와 파워뱅크 기능 제공", "created_at": "2021-09-05", "in_stock": true, "rating": 4.6, "tags": ["스피커", "JBL", "블루투스", "방수", "포터블"]}
{"index": {"_id": "29"}}
{"title": "소니 SRS-XB43 블루투스 스피커", "category": "스피커", "price": 249000, "brand": "Sony", "description": "강력한 저음과 엑스트라 베이스 기능. 파티 라이팅으로 분위기를 업그레이드", "created_at": "2021-06-03", "in_stock": true, "rating": 4.4, "tags": ["스피커", "소니", "블루투스", "파티"]}
{"index": {"_id": "30"}}
{"title": "삼성 갤럭시 워치6 클래식 47mm", "category": "스마트워치", "price": 469000, "brand": "Samsung", "description": "회전 베젤과 정확한 건강 측정. 혈압과 심전도 측정이 가능한 스마트워치", "created_at": "2023-07-26", "in_stock": true, "rating": 4.4, "tags": ["스마트워치", "삼성", "갤럭시워치", "건강"]}
' | jq .errors

echo ">>> [STEP 3] 샘플 데이터 색인 (배치 4/4)"
curl -s -X POST "$ES_HOST/$INDEX/_bulk" \
  -H 'Content-Type: application/json' \
  -d '{"index": {"_id": "31"}}
{"title": "Apple 워치 시리즈 9 GPS 45mm", "category": "스마트워치", "price": 599000, "brand": "Apple", "description": "S9 칩과 더블탭 제스처. 혈중 산소와 체온 측정이 가능한 건강 중심 스마트워치", "created_at": "2023-09-22", "in_stock": true, "rating": 4.7, "tags": ["스마트워치", "애플", "애플워치", "건강"]}
{"index": {"_id": "32"}}
{"title": "가민 Fenix 7X Pro 스마트워치", "category": "스마트워치", "price": 1190000, "brand": "Garmin", "description": "군사 규격 내구성의 아웃도어 스마트워치. 태양광 충전과 정밀 GPS 탑재", "created_at": "2023-05-31", "in_stock": true, "rating": 4.8, "tags": ["스마트워치", "가민", "아웃도어", "GPS"]}
{"index": {"_id": "33"}}
{"title": "파나소닉 에네루프 충전지 4팩", "category": "배터리", "price": 29000, "brand": "Panasonic", "description": "1500회 충방전 가능한 고성능 충전지. 자가방전이 낮아 장기 보관에 적합", "created_at": "2022-03-15", "in_stock": true, "rating": 4.8, "tags": ["배터리", "파나소닉", "충전지", "AA"]}
{"index": {"_id": "34"}}
{"title": "Anker 65W 고속충전 어댑터", "category": "충전기", "price": 39000, "brand": "Anker", "description": "GaN 기술의 소형 고출력 충전기. 노트북부터 스마트폰까지 빠른 충전", "created_at": "2023-01-20", "in_stock": true, "rating": 4.6, "tags": ["충전기", "Anker", "고속충전", "GaN"]}
{"index": {"_id": "35"}}
{"title": "삼성 T7 Shield 외장 SSD 1TB", "category": "저장장치", "price": 139000, "brand": "Samsung", "description": "낙하 방지 설계와 빠른 1050MB/s 전송속도. 소중한 데이터를 안전하게 보관", "created_at": "2022-08-25", "in_stock": true, "rating": 4.7, "tags": ["SSD", "삼성", "외장하드", "1TB"]}
{"index": {"_id": "36"}}
{"title": "웨스턴디지털 My Passport 4TB 외장하드", "category": "저장장치", "price": 119000, "brand": "WD", "description": "USB-C 연결의 대용량 외장하드. 비밀번호 보호와 자동 백업 소프트웨어 포함", "created_at": "2023-06-12", "in_stock": true, "rating": 4.3, "tags": ["외장하드", "WD", "4TB", "백업"]}
{"index": {"_id": "37"}}
{"title": "로지텍 G502 X Plus 무선 게이밍 마우스", "category": "마우스", "price": 179000, "brand": "Logitech", "description": "LIGHTFORCE 하이브리드 스위치와 HERO 25K 센서. 무선임에도 클릭 지연 없는 게이밍 마우스", "created_at": "2022-09-20", "in_stock": true, "rating": 4.5, "tags": ["마우스", "로지텍", "게이밍", "무선"]}
{"index": {"_id": "38"}}
{"title": "레이저 블랙위도우 V4 Pro 기계식 키보드", "category": "키보드", "price": 269000, "brand": "Razer", "description": "레이저 그린 스위치의 쾌감 있는 타건감. RGB 백라이트와 미디어 키 다이얼 탑재", "created_at": "2023-03-02", "in_stock": false, "rating": 4.5, "tags": ["키보드", "레이저", "게이밍", "기계식"]}
{"index": {"_id": "39"}}
{"title": "벨킨 MagSafe 15W 무선충전 패드", "category": "충전기", "price": 59000, "brand": "Belkin", "description": "아이폰 MagSafe 호환 15W 고속 무선충전. 간편한 자석 부착 방식", "created_at": "2023-09-05", "in_stock": true, "rating": 4.3, "tags": ["충전기", "벨킨", "무선충전", "MagSafe", "아이폰"]}
{"index": {"_id": "40"}}
{"title": "필립스 Hue 스마트 조명 스타터팩", "category": "스마트홈", "price": 159000, "brand": "Philips", "description": "음성 및 앱 제어가 가능한 스마트 LED 조명. 1600만 색상으로 분위기 맞춤 설정", "created_at": "2022-11-15", "in_stock": true, "rating": 4.5, "tags": ["스마트홈", "필립스", "조명", "IoT"]}
' | jq .errors

echo ""
echo ">>> [STEP 4] 인덱스 refresh 대기"
sleep 2

echo ">>> [STEP 5] 색인 결과 확인"
curl -s "$ES_HOST/$INDEX/_count" | jq '{index: "'$INDEX'", total_docs: .count}'
echo ""

echo ">>> 카테고리별 분포"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "by_category": {
        "terms": {"field": "category", "size": 20}
      }
    }
  }' | jq '.aggregations.by_category.buckets[] | {category: .key, count: .doc_count}'
echo ""

echo "============================================================"
echo "  샘플 데이터 로딩 완료 ($INDEX 인덱스)"
echo "  다음: 01-match-query.sh"
echo "============================================================"
