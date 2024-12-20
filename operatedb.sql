--상품정보(1)
SELECT p.SHOP_ID, p.NUM, ROUND(NVL(AVG(r.RATING), 0), 2) AS AVERAGE_RATING -- 소수 둘째 자리 반올림
FROM PRODUCTS p
	LEFT JOIN REVIEWS r ON p.SHOP_ID = r.SHOP_ID AND p.NUM = r.NUM
GROUP BY p.SHOP_ID, p.NUM;

--상품정보(2)
SELECT p.SHOP_ID, p.NUM, NVL(COUNT(w.USER_ID), 0) AS TOTAL_WISHLIST_COUNT -- 관심 없는 경우 0으로 표시
FROM PRODUCTS p
	LEFT JOIN WISHLIST w ON p.SHOP_ID = w.SHOP_ID AND p.NUM = w.NUM
GROUP BY p.SHOP_ID, p.NUM;


--구매(1)
SELECT c.USER_ID, c.SHOP_ID, c.NUM, c.QUANTITY, p.PRICE, 
	NVL(
        CASE 
            WHEN d.DISCOUNT_TYPE = '정률할인' THEN p.PRICE * (1 - d.DISCOUNT_RATE / 100)
            WHEN d.DISCOUNT_TYPE = '정액할인' THEN p.PRICE - d.DISCOUNT_RATE
            ELSE p.PRICE
        END, 
        p.PRICE
    ) AS DISCOUNTED_PRICE
FROM CARTS c
JOIN PRODUCTS p 
	ON c.SHOP_ID = p.SHOP_ID AND c.NUM = p.NUM
	LEFT JOIN DISCOUNT d 
	ON c.SHOP_ID = d.SHOP_ID AND c.NUM = d.NUM 
    AND SYSDATE BETWEEN d.DISCOUNT_START_DATE AND d.DISCOUNT_END_DATE
WHERE c.USER_ID = 1;

--구매(2): 외부엔진이 삽입
INSERT INTO ORDERS (ORDER_ID, USER_ID, ORDER_DATE, ORDER_STATUS, TOTAL_AMOUNT, PAYMENT_METHOD, PAYMENT_TIME, PAYMENT_STATUS, SHIPPING_STATUS, TRACKING_NUMBER)
VALUES (
    6, -- 외부 엔진에서 생성한 주문 ID
    1, -- USER_ID
    SYSDATE, 
    '결제완료', 
    98820, -- 외부 엔진에서 반환한 총 금액
    '신용카드', -- 사용자가 선택한 결제 방법
    SYSDATE, 
    '결제완료', 
    '상품준비중', 
    NULL -- 추적 번호는 이후 업데이트
);

--구매(3): 외부엔진이 삽입
INSERT ALL
    INTO ORDER_ITEMS (ORDER_ID, SHOP_ID, NUM, QUANTITY, ORDER_PRICE) VALUES (6, 1, 1, 2, 26910) -- 첫 번째 데이터
    INTO ORDER_ITEMS (ORDER_ID, SHOP_ID, NUM, QUANTITY, ORDER_PRICE) VALUES (6, 1, 2, 1, 45000) -- 두 번째 데이터
SELECT * FROM DUAL;


SELECT * FROM order_items where order_id=6;



--교환 및 환불(1)
SELECT * FROM RETURNS_AND_EXCHANGES;
INSERT INTO RETURNS_AND_EXCHANGES (
    USER_ID, 
    ORDER_ID, 
    SHOP_ID, 
    NUM, 
    TYPE, 
    REQUEST_DATE, 
    REASON, 
    REASON_ADD, 
    STATUS
)
VALUES (
    2,                     -- USER_ID
    2,                     -- ORDER_ID
    2,                     -- SHOP_ID
    1,                     -- NUM (상품 번호)
    '반품',                -- TYPE (교환 또는 환불)
    TO_DATE('2024-12-06', 'YYYY-MM-DD'), -- REQUEST_DATE
    '단순변심',            -- REASON
    '색상이 생각했던 것과 달라요', -- REASON_ADD
    '처리 중'                 -- STATUS
);

--교환 및 환불(2)
UPDATE RETURNS_AND_EXCHANGES
SET 
    STATUS = '승인' 
WHERE 
	ORDER_ID = 2
    AND SHOP_ID = 2
    AND NUM = 1;
   
--교환 및 환불(3)
UPDATE ORDER_ITEMS
SET 
    IS_REFUNDED = 'Y'
WHERE 
    ORDER_ID = 2 
    AND SHOP_ID = 2 
    AND NUM = 1; 
   
UPDATE ORDERS
SET TOTAL_AMOUNT = TOTAL_AMOUNT - (
    SELECT ORDER_PRICE * QUANTITY
    FROM ORDER_ITEMS
    WHERE ORDER_ID = 2 AND IS_REFUNDED = 'Y'
)
WHERE ORDER_ID = 2;

   
SELECT * FROM ORDERS WHERE order_id=2;

--환불 금액 추산
SELECT 
    M.USER_ID, 
    M.MEMBERSHIP_TIER, 
    NVL(SUM(OI.QUANTITY * OI.ORDER_PRICE), 0) AS TOTAL_REFUND_AMOUNT
FROM 
    MEMBERSHIP M
LEFT JOIN 
    ORDER_ITEMS OI
ON 
    M.USER_ID = OI.ORDER_ID -- USER_ID와 ORDER_ID 연결
WHERE 
    M.USER_ID = 2 -- 특정 유저 ID
    AND OI.ORDER_ID = 2 -- 특정 주문 ID
    AND oi.shop_id= 2
    AND oi.num = 1
    AND OI.IS_REFUNDED = 'Y' -- 환불된 항목만 포함
GROUP BY 
    M.USER_ID, M.MEMBERSHIP_TIER;

--환불 금액을 포인트에서 제거
INSERT INTO POINTS (
    USER_ID, 
    POINTS, 
    TRANSACTION_SEQUENCE, 
    TRANSACTION_DATE
)
VALUES (
    2, -- USER_ID
    -2250, -- 환불로 인한 포인트 회수 (음수로 표시), 실버 멤버십 0.05*45000
    (SELECT NVL(MAX(TRANSACTION_SEQUENCE), 0) + 1 FROM POINTS WHERE USER_ID = 2), -- 유저의 다음 시퀀스
    SYSDATE -- 현재 날짜 및 시간
);

SELECT * FROM POINTS WHERE USER_ID=2;


 --할인 표시
SELECT 
    P.SHOP_ID,
    P.NUM,
    P.PRODUCT_NAME,
    P.PRICE AS ORIGINAL_PRICE,
    D.DISCOUNT_RATE,
    D.DISCOUNT_TYPE,
    CASE 
        WHEN D.DISCOUNT_TYPE = '정률할인' THEN ROUND(P.PRICE * (1 - D.DISCOUNT_RATE / 100), 2)
        WHEN D.DISCOUNT_TYPE = '정액할인' THEN GREATEST(P.PRICE - D.DISCOUNT_RATE, 0)
        ELSE P.PRICE -- 할인 정보가 없거나 유형이 알 수 없을 때 원래 가격
    END AS FINAL_PRICE
FROM 
    PRODUCTS P
JOIN 
    DISCOUNT D 
ON 
    P.SHOP_ID = D.SHOP_ID 
    AND P.NUM = D.NUM
WHERE 
    SYSDATE BETWEEN D.DISCOUNT_START_DATE AND D.DISCOUNT_END_DATE;
   
    
--적립 시나리오
--1    
SELECT 
    O.USER_ID,
    OI.ORDER_ID,
    OI.SHOP_ID,
    OI.NUM,
    OI.ORDER_PRICE,
    M.MEMBERSHIP_TIER
FROM 
    ORDER_ITEMS OI
JOIN 
    ORDERS O ON OI.ORDER_ID = O.ORDER_ID
JOIN 
    MEMBERSHIP M ON O.USER_ID = M.USER_ID
WHERE 
    OI.ORDER_ID = 4; -- 특정 주문 ID
--2
INSERT INTO POINTS (
    USER_ID,
    POINTS,
    TRANSACTION_SEQUENCE,
    TRANSACTION_DATE
)
SELECT 
    5, -- 외부 엔진에서 반환된 USER_ID
    17100, -- 외부 엔진에서 반환된 적립 포인트
    COALESCE(MAX(TRANSACTION_SEQUENCE), 0) + 1 AS TRANSACTION_SEQUENCE, -- 순번 계산
    SYSDATE -- 현재 날짜
FROM 
    POINTS
WHERE 
    USER_ID = 5
GROUP BY 
    USER_ID;
   
SELECT * FROM points WHERE user_id=5;

--리뷰
-- 중복된 리뷰가 없을 경우에만 삽입하도록 처리
INSERT INTO REVIEWS (
    USER_ID, 
    ORDER_ID, 
    SHOP_ID, 
    NUM, 
    REVIEW_CONTENT, 
    RATING, 
    REVIEW_DATE
)
SELECT 
    1,                                    -- USER_ID
    1,                                    -- ORDER_ID
    1,                                    -- SHOP_ID
    1,                                    -- NUM
    '좋은 상품입니다. 다음에도 구매하고 싶어요',     -- REVIEW_CONTENT
    5,                                    -- RATING
    TO_DATE('2024-12-06', 'YYYY-MM-DD')    -- REVIEW_DATE
FROM dual
WHERE NOT EXISTS (
    SELECT 1
    FROM REVIEWS
    WHERE USER_ID = 1
      AND ORDER_ID = 1
      AND SHOP_ID = 1
      AND NUM = 1
);

--판매자 답글
INSERT INTO REPLY (USER_ID, ORDER_ID, SHOP_ID, NUM, REPLY_CONTENT, REPLY_AT, SELLER_ID)
VALUES (
    7, -- USER_ID
    5, -- ORDER_ID
    1, -- SHOP_ID
    1, -- NUM
    '소중한 리뷰 감사합니다. 앞으로도 만족스러운 상품을 제공하겠습니다.', -- REPLY_CONTENT
    TO_DATE('2024-12-11', 'YYYY-MM-DD'), -- REPLY_AT
    2 -- SELLER_ID
);



--1:1문의
INSERT INTO INQUIRIES (
    USER_ID, 
    SHOP_ID, 
    NUM, 
    INQUIRY_CONTENT, 
    INQUIRY_DATE, 
    RESPONSE_CONTENT, 
    RESPONSE_DATE, 
    SELLER_ID
) VALUES (
    3, -- USER_ID: 문의를 등록한 사용자
    1, -- SHOP_ID: 문의가 발생한 상점 ID
    2, -- NUM: 문의 상품 ID
    '이 상품 재입고 예정이 있나요?', -- INQUIRY_CONTENT: 문의 내용
    TO_DATE('2024-12-20', 'YYYY-MM-DD'), -- INQUIRY_DATE: 문의 날짜
    NULL, -- RESPONSE_CONTENT: 초기값 NULL (답변 없음)
    NULL, -- RESPONSE_DATE: 초기값 NULL (답변 없음)
    NULL  -- SELLER_ID: 초기값 NULL (답변한 판매자 없음)
);

SELECT * FROM INQUIRIES WHERE SHOP_ID=1 AND NUM=2;


UPDATE INQUIRIES
SET 
    RESPONSE_CONTENT = '다음 주 중으로 재입고 예정입니다.', -- 판매자 답변 내용
    RESPONSE_DATE = TO_DATE('2024-12-21', 'YYYY-MM-DD'), -- 답변 날짜
    SELLER_ID = 1 -- 답변한 판매자 ID
WHERE 
    USER_ID = 3 
    AND SHOP_ID = 1 
    AND NUM = 2; -- 특정 문의를 식별하는 조건
 
    


--멤버십
   
UPDATE MEMBERSHIP
SET 
    MEMBERSHIP_TIER = 'GOLD',   -- 외부 엔진에서 제공한 새로운 등급
    TIER_START_DATE = SYSDATE,     -- 현재 날짜를 등급 변경일로 설정
    ANNUAL_PURCHASE_AMOUNT = 0     -- 연간 구매 금액 초기화
WHERE 
    USER_ID = 1;
   
SELECT * FROM membership;


UPDATE MEMBERSHIP M
SET ANNUAL_PURCHASE_AMOUNT = ANNUAL_PURCHASE_AMOUNT + (
    SELECT 
        SUM(OI.ORDER_PRICE * OI.QUANTITY) 
    FROM 
        ORDER_ITEMS OI
    JOIN ORDERS O ON O.ORDER_ID = OI.ORDER_ID
    WHERE 
        O.USER_ID = M.USER_ID 
        AND O.ORDER_DATE > M.LAST_UPDATED_DATE -- 마지막 누적 이후의 금액만 계산
)
WHERE EXISTS (
    SELECT 1
    FROM ORDER_ITEMS OI
    JOIN ORDERS O ON O.ORDER_ID = OI.ORDER_ID
    WHERE 
        O.USER_ID = M.USER_ID 
        AND O.ORDER_DATE > M.LAST_UPDATED_DATE -- 새 구매가 존재하는 경우만 업데이트
);

UPDATE MEMBERSHIP
SET LAST_UPDATED_DATE = SYSDATE;




--검색 엔진
--셔츠 상품을 검색한다. 이때 검색엔진은 관심목록/추천상품 등의 데이터까지 참고한다.
-- 이 경우 인풋 데이터만 동작을 확인, 아웃풋 데이터는 확인하지 않는다.

SELECT * FROM PRODUCTS WHERE CATEGORY_NAME='셔츠';
SELECT * FROM WISHLIST WHERE USER_ID=1;
SELECT * FROM RECOMMEND WHERE USER_ID=1;
SELECT * FROM CARTS WHERE USER_ID=1;

--추천엔진
SELECT * FROM WISHLIST WHERE USER_ID=3;
SELECT * 
FROM ORDER_ITEMS 
WHERE ORDER_ID IN (
    SELECT ORDER_ID 
    FROM ORDERS 
    WHERE USER_ID = 3
);
SELECT * FROM CARTS WHERE USER_ID=3;
SELECT * FROM REVIEWS WHERE USER_ID=3;

INSERT INTO WISHLIST (USER_ID, SHOP_ID, NUM, ADDED_DATE)
	VALUES (3, 1, 2, TO_DATE('2024-12-20', 'YYYY-MM-DD'));

SELECT * FROM WISHLIST WHERE USER_ID=3;





