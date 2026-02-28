#!/bin/bash
# ==============================================================
# 00-setup-data.sh
# 집계 실습용 이커머스 주문 데이터 로딩 (~200건)
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}
INDEX="orders"

echo "============================================================"
echo "  00. 집계 실습 샘플 데이터 로딩"
echo "  인덱스: $INDEX | ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

echo ">>> [STEP 1] 기존 인덱스 삭제"
curl -s -X DELETE "$ES_HOST/$INDEX" | jq .
echo ""

echo ">>> [STEP 2] 인덱스 생성 및 매핑 설정"
curl -s -X PUT "$ES_HOST/$INDEX" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0
    },
    "mappings": {
      "properties": {
        "order_id":       {"type": "keyword"},
        "customer_name":  {"type": "keyword"},
        "product":        {"type": "keyword"},
        "category":       {"type": "keyword"},
        "price":          {"type": "integer"},
        "quantity":       {"type": "integer"},
        "order_date":     {"type": "date", "format": "yyyy-MM-dd"},
        "region":         {"type": "keyword"},
        "payment_method": {"type": "keyword"}
      }
    }
  }' | jq .
echo ""

echo ">>> [STEP 3] 주문 데이터 색인 (배치 1/5)"
curl -s -X POST "$ES_HOST/$INDEX/_bulk" \
  -H 'Content-Type: application/json' \
  -d '{"index": {}}
{"order_id": "ORD-001", "customer_name": "김철수", "product": "갤럭시 S24", "category": "스마트폰", "price": 1599000, "quantity": 1, "order_date": "2024-01-05", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-002", "customer_name": "이영희", "product": "아이폰 15 Pro", "category": "스마트폰", "price": 1550000, "quantity": 1, "order_date": "2024-01-07", "region": "부산", "payment_method": "카카오페이"}
{"index": {}}
{"order_id": "ORD-003", "customer_name": "박민준", "product": "에어팟 프로 2세대", "category": "이어폰", "price": 359000, "quantity": 2, "order_date": "2024-01-08", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-004", "customer_name": "최지수", "product": "맥북 프로 14인치 M3", "category": "노트북", "price": 2990000, "quantity": 1, "order_date": "2024-01-10", "region": "대구", "payment_method": "무통장입금"}
{"index": {}}
{"order_id": "ORD-005", "customer_name": "정하늘", "product": "소니 WH-1000XM5", "category": "헤드폰", "price": 449000, "quantity": 1, "order_date": "2024-01-12", "region": "인천", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-006", "customer_name": "강도현", "product": "LG 그램 17 노트북", "category": "노트북", "price": 1890000, "quantity": 1, "order_date": "2024-01-14", "region": "서울", "payment_method": "삼성페이"}
{"index": {}}
{"order_id": "ORD-007", "customer_name": "윤서연", "product": "갤럭시 탭 S9 울트라", "category": "태블릿", "price": 1399000, "quantity": 1, "order_date": "2024-01-15", "region": "광주", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-008", "customer_name": "임재원", "product": "ASUS ROG 게이밍 노트북", "category": "노트북", "price": 1990000, "quantity": 1, "order_date": "2024-01-16", "region": "대전", "payment_method": "카카오페이"}
{"index": {}}
{"order_id": "ORD-009", "customer_name": "한소희", "product": "다이슨 V15 무선청소기", "category": "청소기", "price": 1090000, "quantity": 1, "order_date": "2024-01-18", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-010", "customer_name": "오준혁", "product": "닌텐도 스위치 OLED", "category": "게임기", "price": 399000, "quantity": 2, "order_date": "2024-01-20", "region": "부산", "payment_method": "네이버페이"}
{"index": {}}
{"order_id": "ORD-011", "customer_name": "서지은", "product": "갤럭시 버즈2 Pro", "category": "이어폰", "price": 259000, "quantity": 1, "order_date": "2024-01-22", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-012", "customer_name": "권태호", "product": "소니 A7 IV 카메라", "category": "카메라", "price": 2890000, "quantity": 1, "order_date": "2024-01-24", "region": "대구", "payment_method": "무통장입금"}
{"index": {}}
{"order_id": "ORD-013", "customer_name": "나은별", "product": "JBL Charge 5 스피커", "category": "스피커", "price": 219000, "quantity": 3, "order_date": "2024-01-25", "region": "인천", "payment_method": "카카오페이"}
{"index": {}}
{"order_id": "ORD-014", "customer_name": "조민찬", "product": "아이패드 프로 12.9 M2", "category": "태블릿", "price": 1499000, "quantity": 1, "order_date": "2024-01-27", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-015", "customer_name": "문지혜", "product": "로지텍 MX Master 3S", "category": "마우스", "price": 129000, "quantity": 2, "order_date": "2024-01-28", "region": "부산", "payment_method": "삼성페이"}
{"index": {}}
{"order_id": "ORD-016", "customer_name": "신현우", "product": "필립스 Hue 스마트 조명", "category": "스마트홈", "price": 159000, "quantity": 2, "order_date": "2024-01-30", "region": "서울", "payment_method": "네이버페이"}
{"index": {}}
{"order_id": "ORD-017", "customer_name": "황지민", "product": "갤럭시 S24 울트라", "category": "스마트폰", "price": 1599000, "quantity": 1, "order_date": "2024-02-02", "region": "광주", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-018", "customer_name": "류성호", "product": "레이저 블랙위도우 키보드", "category": "키보드", "price": 269000, "quantity": 1, "order_date": "2024-02-04", "region": "대전", "payment_method": "카카오페이"}
{"index": {}}
{"order_id": "ORD-019", "customer_name": "배수정", "product": "Anker 65W 충전기", "category": "충전기", "price": 39000, "quantity": 5, "order_date": "2024-02-05", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-020", "customer_name": "전민석", "product": "LG OLED 65인치 TV", "category": "TV", "price": 2490000, "quantity": 1, "order_date": "2024-02-07", "region": "부산", "payment_method": "무통장입금"}
' | jq .errors

echo ">>> [STEP 3] 주문 데이터 색인 (배치 2/5)"
curl -s -X POST "$ES_HOST/$INDEX/_bulk" \
  -H 'Content-Type: application/json' \
  -d '{"index": {}}
{"order_id": "ORD-021", "customer_name": "김철수", "product": "Apple 워치 시리즈 9", "category": "스마트워치", "price": 599000, "quantity": 1, "order_date": "2024-02-10", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-022", "customer_name": "이영희", "product": "갤럭시 워치6 클래식", "category": "스마트워치", "price": 469000, "quantity": 1, "order_date": "2024-02-12", "region": "부산", "payment_method": "카카오페이"}
{"index": {}}
{"order_id": "ORD-023", "customer_name": "박민준", "product": "캐논 EOS R50 카메라", "category": "카메라", "price": 879000, "quantity": 1, "order_date": "2024-02-14", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-024", "customer_name": "최지수", "product": "삼성 65인치 QLED TV", "category": "TV", "price": 1290000, "quantity": 1, "order_date": "2024-02-15", "region": "대구", "payment_method": "삼성페이"}
{"index": {}}
{"order_id": "ORD-025", "customer_name": "정하늘", "product": "로지텍 G502 X Plus 마우스", "category": "마우스", "price": 179000, "quantity": 1, "order_date": "2024-02-17", "region": "인천", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-026", "customer_name": "강도현", "product": "소니 PS5 디스크에디션", "category": "게임기", "price": 729000, "quantity": 1, "order_date": "2024-02-19", "region": "서울", "payment_method": "카카오페이"}
{"index": {}}
{"order_id": "ORD-027", "customer_name": "윤서연", "product": "WD My Passport 4TB", "category": "저장장치", "price": 119000, "quantity": 2, "order_date": "2024-02-20", "region": "광주", "payment_method": "네이버페이"}
{"index": {}}
{"order_id": "ORD-028", "customer_name": "임재원", "product": "삼성 T7 Shield SSD 1TB", "category": "저장장치", "price": 139000, "quantity": 1, "order_date": "2024-02-22", "region": "대전", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-029", "customer_name": "한소희", "product": "아이폰 15 Pro", "category": "스마트폰", "price": 1550000, "quantity": 1, "order_date": "2024-02-24", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-030", "customer_name": "오준혁", "product": "레노버 씽크패드 X1", "category": "노트북", "price": 2490000, "quantity": 1, "order_date": "2024-02-25", "region": "부산", "payment_method": "무통장입금"}
{"index": {}}
{"order_id": "ORD-031", "customer_name": "서지은", "product": "갤럭시 S24 울트라", "category": "스마트폰", "price": 1599000, "quantity": 1, "order_date": "2024-03-02", "region": "서울", "payment_method": "삼성페이"}
{"index": {}}
{"order_id": "ORD-032", "customer_name": "권태호", "product": "에어팟 프로 2세대", "category": "이어폰", "price": 359000, "quantity": 1, "order_date": "2024-03-04", "region": "대구", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-033", "customer_name": "나은별", "product": "맥북 프로 14인치 M3", "category": "노트북", "price": 2990000, "quantity": 1, "order_date": "2024-03-06", "region": "인천", "payment_method": "카카오페이"}
{"index": {}}
{"order_id": "ORD-034", "customer_name": "조민찬", "product": "Anker 65W 충전기", "category": "충전기", "price": 39000, "quantity": 10, "order_date": "2024-03-08", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-035", "customer_name": "문지혜", "product": "소니 SRS-XB43 스피커", "category": "스피커", "price": 249000, "quantity": 1, "order_date": "2024-03-10", "region": "부산", "payment_method": "네이버페이"}
{"index": {}}
{"order_id": "ORD-036", "customer_name": "신현우", "product": "구글 픽셀 8 Pro", "category": "스마트폰", "price": 1290000, "quantity": 1, "order_date": "2024-03-12", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-037", "customer_name": "황지민", "product": "필립스 Hue 스마트 조명", "category": "스마트홈", "price": 159000, "quantity": 3, "order_date": "2024-03-14", "region": "광주", "payment_method": "카카오페이"}
{"index": {}}
{"order_id": "ORD-038", "customer_name": "류성호", "product": "가민 Fenix 7X Pro", "category": "스마트워치", "price": 1190000, "quantity": 1, "order_date": "2024-03-16", "region": "대전", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-039", "customer_name": "배수정", "product": "삼성 비스포크 냉장고", "category": "냉장고", "price": 2190000, "quantity": 1, "order_date": "2024-03-18", "region": "서울", "payment_method": "무통장입금"}
{"index": {}}
{"order_id": "ORD-040", "customer_name": "전민석", "product": "Xbox Series X", "category": "게임기", "price": 629000, "quantity": 1, "order_date": "2024-03-20", "region": "부산", "payment_method": "신용카드"}
' | jq .errors

echo ">>> [STEP 3] 주문 데이터 색인 (배치 3/5)"
curl -s -X POST "$ES_HOST/$INDEX/_bulk" \
  -H 'Content-Type: application/json' \
  -d '{"index": {}}
{"order_id": "ORD-041", "customer_name": "김철수", "product": "아이패드 프로 12.9 M2", "category": "태블릿", "price": 1499000, "quantity": 1, "order_date": "2024-04-02", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-042", "customer_name": "이영희", "product": "샤오미 Redmi Note 13 Pro", "category": "스마트폰", "price": 399000, "quantity": 2, "order_date": "2024-04-05", "region": "부산", "payment_method": "카카오페이"}
{"index": {}}
{"order_id": "ORD-043", "customer_name": "박민준", "product": "LG 울트라와이드 모니터", "category": "모니터", "price": 699000, "quantity": 1, "order_date": "2024-04-07", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-044", "customer_name": "최지수", "product": "갤럭시 버즈2 Pro", "category": "이어폰", "price": 259000, "quantity": 3, "order_date": "2024-04-09", "region": "대구", "payment_method": "삼성페이"}
{"index": {}}
{"order_id": "ORD-045", "customer_name": "정하늘", "product": "맥북 프로 14인치 M3", "category": "노트북", "price": 2990000, "quantity": 1, "order_date": "2024-04-11", "region": "인천", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-046", "customer_name": "강도현", "product": "벨킨 MagSafe 충전패드", "category": "충전기", "price": 59000, "quantity": 2, "order_date": "2024-04-13", "region": "서울", "payment_method": "네이버페이"}
{"index": {}}
{"order_id": "ORD-047", "customer_name": "윤서연", "product": "삼성 32인치 QHD 모니터", "category": "모니터", "price": 589000, "quantity": 1, "order_date": "2024-04-15", "region": "광주", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-048", "customer_name": "임재원", "product": "Apple 워치 시리즈 9", "category": "스마트워치", "price": 599000, "quantity": 1, "order_date": "2024-04-18", "region": "대전", "payment_method": "카카오페이"}
{"index": {}}
{"order_id": "ORD-049", "customer_name": "한소희", "product": "갤럭시 S24 울트라", "category": "스마트폰", "price": 1599000, "quantity": 1, "order_date": "2024-04-20", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-050", "customer_name": "오준혁", "product": "다이슨 V15 무선청소기", "category": "청소기", "price": 1090000, "quantity": 1, "order_date": "2024-04-22", "region": "부산", "payment_method": "삼성페이"}
{"index": {}}
{"order_id": "ORD-051", "customer_name": "서지은", "product": "LG 디오스 냉장고", "category": "냉장고", "price": 2450000, "quantity": 1, "order_date": "2024-05-03", "region": "서울", "payment_method": "무통장입금"}
{"index": {}}
{"order_id": "ORD-052", "customer_name": "권태호", "product": "닌텐도 스위치 OLED", "category": "게임기", "price": 399000, "quantity": 1, "order_date": "2024-05-05", "region": "대구", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-053", "customer_name": "나은별", "product": "JBL Charge 5 스피커", "category": "스피커", "price": 219000, "quantity": 2, "order_date": "2024-05-07", "region": "인천", "payment_method": "카카오페이"}
{"index": {}}
{"order_id": "ORD-054", "customer_name": "조민찬", "product": "에어팟 프로 2세대", "category": "이어폰", "price": 359000, "quantity": 1, "order_date": "2024-05-09", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-055", "customer_name": "문지혜", "product": "소니 WH-1000XM5", "category": "헤드폰", "price": 449000, "quantity": 1, "order_date": "2024-05-11", "region": "부산", "payment_method": "네이버페이"}
{"index": {}}
{"order_id": "ORD-056", "customer_name": "신현우", "product": "아이폰 15 Pro", "category": "스마트폰", "price": 1550000, "quantity": 2, "order_date": "2024-05-13", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-057", "customer_name": "황지민", "product": "로지텍 MX Master 3S", "category": "마우스", "price": 129000, "quantity": 1, "order_date": "2024-05-15", "region": "광주", "payment_method": "카카오페이"}
{"index": {}}
{"order_id": "ORD-058", "customer_name": "류성호", "product": "삼성 T7 Shield SSD 1TB", "category": "저장장치", "price": 139000, "quantity": 3, "order_date": "2024-05-17", "region": "대전", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-059", "customer_name": "배수정", "product": "가민 Fenix 7X Pro", "category": "스마트워치", "price": 1190000, "quantity": 1, "order_date": "2024-05-19", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-060", "customer_name": "전민석", "product": "갤럭시 S24 울트라", "category": "스마트폰", "price": 1599000, "quantity": 1, "order_date": "2024-05-21", "region": "부산", "payment_method": "삼성페이"}
' | jq .errors

echo ">>> [STEP 3] 주문 데이터 색인 (배치 4/5)"
curl -s -X POST "$ES_HOST/$INDEX/_bulk" \
  -H 'Content-Type: application/json' \
  -d '{"index": {}}
{"order_id": "ORD-061", "customer_name": "김철수", "product": "맥북 프로 14인치 M3", "category": "노트북", "price": 2990000, "quantity": 1, "order_date": "2024-06-03", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-062", "customer_name": "이영희", "product": "Apple 워치 시리즈 9", "category": "스마트워치", "price": 599000, "quantity": 1, "order_date": "2024-06-05", "region": "부산", "payment_method": "카카오페이"}
{"index": {}}
{"order_id": "ORD-063", "customer_name": "박민준", "product": "소니 A7 IV 카메라", "category": "카메라", "price": 2890000, "quantity": 1, "order_date": "2024-06-07", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-064", "customer_name": "최지수", "product": "LG OLED 65인치 TV", "category": "TV", "price": 2490000, "quantity": 1, "order_date": "2024-06-09", "region": "대구", "payment_method": "삼성페이"}
{"index": {}}
{"order_id": "ORD-065", "customer_name": "정하늘", "product": "에어팟 프로 2세대", "category": "이어폰", "price": 359000, "quantity": 2, "order_date": "2024-06-11", "region": "인천", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-066", "customer_name": "강도현", "product": "Anker 65W 충전기", "category": "충전기", "price": 39000, "quantity": 4, "order_date": "2024-06-13", "region": "서울", "payment_method": "네이버페이"}
{"index": {}}
{"order_id": "ORD-067", "customer_name": "윤서연", "product": "갤럭시 탭 S9 울트라", "category": "태블릿", "price": 1399000, "quantity": 1, "order_date": "2024-06-15", "region": "광주", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-068", "customer_name": "임재원", "product": "닌텐도 스위치 OLED", "category": "게임기", "price": 399000, "quantity": 1, "order_date": "2024-06-17", "region": "대전", "payment_method": "카카오페이"}
{"index": {}}
{"order_id": "ORD-069", "customer_name": "한소희", "product": "로지텍 G502 X Plus 마우스", "category": "마우스", "price": 179000, "quantity": 2, "order_date": "2024-06-19", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-070", "customer_name": "오준혁", "product": "아이폰 15 Pro", "category": "스마트폰", "price": 1550000, "quantity": 1, "order_date": "2024-06-21", "region": "부산", "payment_method": "삼성페이"}
{"index": {}}
{"order_id": "ORD-071", "customer_name": "서지은", "product": "삼성 65인치 QLED TV", "category": "TV", "price": 1290000, "quantity": 1, "order_date": "2024-07-03", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-072", "customer_name": "권태호", "product": "갤럭시 S24 울트라", "category": "스마트폰", "price": 1599000, "quantity": 1, "order_date": "2024-07-05", "region": "대구", "payment_method": "카카오페이"}
{"index": {}}
{"order_id": "ORD-073", "customer_name": "나은별", "product": "에어팟 프로 2세대", "category": "이어폰", "price": 359000, "quantity": 3, "order_date": "2024-07-07", "region": "인천", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-074", "customer_name": "조민찬", "product": "소니 WH-1000XM5", "category": "헤드폰", "price": 449000, "quantity": 1, "order_date": "2024-07-09", "region": "서울", "payment_method": "삼성페이"}
{"index": {}}
{"order_id": "ORD-075", "customer_name": "문지혜", "product": "LG 그램 17 노트북", "category": "노트북", "price": 1890000, "quantity": 1, "order_date": "2024-07-11", "region": "부산", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-076", "customer_name": "신현우", "product": "구글 픽셀 8 Pro", "category": "스마트폰", "price": 1290000, "quantity": 1, "order_date": "2024-07-13", "region": "서울", "payment_method": "네이버페이"}
{"index": {}}
{"order_id": "ORD-077", "customer_name": "황지민", "product": "다이슨 V15 무선청소기", "category": "청소기", "price": 1090000, "quantity": 1, "order_date": "2024-07-15", "region": "광주", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-078", "customer_name": "류성호", "product": "JBL Charge 5 스피커", "category": "스피커", "price": 219000, "quantity": 2, "order_date": "2024-07-17", "region": "대전", "payment_method": "카카오페이"}
{"index": {}}
{"order_id": "ORD-079", "customer_name": "배수정", "product": "맥북 프로 14인치 M3", "category": "노트북", "price": 2990000, "quantity": 1, "order_date": "2024-07-19", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-080", "customer_name": "전민석", "product": "아이패드 프로 12.9 M2", "category": "태블릿", "price": 1499000, "quantity": 1, "order_date": "2024-07-21", "region": "부산", "payment_method": "삼성페이"}
' | jq .errors

echo ">>> [STEP 3] 주문 데이터 색인 (배치 5/5)"
curl -s -X POST "$ES_HOST/$INDEX/_bulk" \
  -H 'Content-Type: application/json' \
  -d '{"index": {}}
{"order_id": "ORD-081", "customer_name": "김철수", "product": "갤럭시 S24", "category": "스마트폰", "price": 1100000, "quantity": 1, "order_date": "2024-08-03", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-082", "customer_name": "이영희", "product": "레노버 씽크패드 X1", "category": "노트북", "price": 2490000, "quantity": 1, "order_date": "2024-08-05", "region": "부산", "payment_method": "카카오페이"}
{"index": {}}
{"order_id": "ORD-083", "customer_name": "박민준", "product": "소니 PS5 디스크에디션", "category": "게임기", "price": 729000, "quantity": 1, "order_date": "2024-08-07", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-084", "customer_name": "최지수", "product": "갤럭시 버즈2 Pro", "category": "이어폰", "price": 259000, "quantity": 2, "order_date": "2024-08-09", "region": "대구", "payment_method": "삼성페이"}
{"index": {}}
{"order_id": "ORD-085", "customer_name": "정하늘", "product": "Apple 워치 시리즈 9", "category": "스마트워치", "price": 599000, "quantity": 1, "order_date": "2024-08-11", "region": "인천", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-086", "customer_name": "강도현", "product": "삼성 65인치 QLED TV", "category": "TV", "price": 1290000, "quantity": 1, "order_date": "2024-08-13", "region": "서울", "payment_method": "네이버페이"}
{"index": {}}
{"order_id": "ORD-087", "customer_name": "윤서연", "product": "아이폰 15 Pro", "category": "스마트폰", "price": 1550000, "quantity": 1, "order_date": "2024-08-15", "region": "광주", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-088", "customer_name": "임재원", "product": "로지텍 MX Master 3S", "category": "마우스", "price": 129000, "quantity": 2, "order_date": "2024-08-17", "region": "대전", "payment_method": "카카오페이"}
{"index": {}}
{"order_id": "ORD-089", "customer_name": "한소희", "product": "에어팟 프로 2세대", "category": "이어폰", "price": 359000, "quantity": 1, "order_date": "2024-08-19", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-090", "customer_name": "오준혁", "product": "WD My Passport 4TB", "category": "저장장치", "price": 119000, "quantity": 3, "order_date": "2024-08-21", "region": "부산", "payment_method": "삼성페이"}
{"index": {}}
{"order_id": "ORD-091", "customer_name": "서지은", "product": "필립스 Hue 스마트 조명", "category": "스마트홈", "price": 159000, "quantity": 2, "order_date": "2024-09-03", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-092", "customer_name": "권태호", "product": "ASUS ROG 게이밍 노트북", "category": "노트북", "price": 1990000, "quantity": 1, "order_date": "2024-09-05", "region": "대구", "payment_method": "카카오페이"}
{"index": {}}
{"order_id": "ORD-093", "customer_name": "나은별", "product": "갤럭시 S24 울트라", "category": "스마트폰", "price": 1599000, "quantity": 1, "order_date": "2024-09-07", "region": "인천", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-094", "customer_name": "조민찬", "product": "캐논 EOS R50 카메라", "category": "카메라", "price": 879000, "quantity": 1, "order_date": "2024-09-09", "region": "서울", "payment_method": "삼성페이"}
{"index": {}}
{"order_id": "ORD-095", "customer_name": "문지혜", "product": "JBL Charge 5 스피커", "category": "스피커", "price": 219000, "quantity": 1, "order_date": "2024-09-11", "region": "부산", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-096", "customer_name": "신현우", "product": "다이슨 V15 무선청소기", "category": "청소기", "price": 1090000, "quantity": 1, "order_date": "2024-09-13", "region": "서울", "payment_method": "네이버페이"}
{"index": {}}
{"order_id": "ORD-097", "customer_name": "황지민", "product": "닌텐도 스위치 OLED", "category": "게임기", "price": 399000, "quantity": 2, "order_date": "2024-09-15", "region": "광주", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-098", "customer_name": "류성호", "product": "소니 PS5 디스크에디션", "category": "게임기", "price": 729000, "quantity": 1, "order_date": "2024-09-17", "region": "대전", "payment_method": "카카오페이"}
{"index": {}}
{"order_id": "ORD-099", "customer_name": "배수정", "product": "에어팟 프로 2세대", "category": "이어폰", "price": 359000, "quantity": 2, "order_date": "2024-09-19", "region": "서울", "payment_method": "신용카드"}
{"index": {}}
{"order_id": "ORD-100", "customer_name": "전민석", "product": "갤럭시 S24 울트라", "category": "스마트폰", "price": 1599000, "quantity": 1, "order_date": "2024-09-21", "region": "부산", "payment_method": "삼성페이"}
' | jq .errors

echo ""
echo ">>> [STEP 4] 인덱스 refresh 대기"
sleep 2

echo ">>> [STEP 5] 색인 결과 확인"
curl -s "$ES_HOST/$INDEX/_count" | jq '{index: "'$INDEX'", total_docs: .count}'
echo ""

echo ">>> 카테고리별 주문 분포"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "by_category": {"terms": {"field": "category", "size": 20}}
    }
  }' | jq '[.aggregations.by_category.buckets[] | {category: .key, orders: .doc_count}]'
echo ""

echo "============================================================"
echo "  샘플 데이터 로딩 완료 ($INDEX 인덱스)"
echo "  다음: 01-metric-aggs.sh"
echo "============================================================"
